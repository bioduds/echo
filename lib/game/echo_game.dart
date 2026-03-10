import 'dart:math';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import '../services/ai_service.dart';
import '../services/system_scanner.dart';
import '../services/os_controller.dart';
import 'player.dart';
import 'echo_entity.dart';
import 'ghost_entity.dart';
import 'arena.dart';
import 'hud.dart';
import 'data_reveal.dart';
import 'phase_config.dart';

class EchoGame extends FlameGame
    with HasKeyboardHandlerComponents, HasCollisionDetection, TapCallbacks, MouseMovementDetector {
  final String backendUrl;
  late final String sessionId;

  late Player player;
  late EchoEntity echo;
  late AiService ai;
  late DataRevealPanel dataReveal;

  int round = 1;
  bool roundActive = false;
  String? aiTaunt;
  String? behaviorProfile;
  String? echoPlaystyle;
  bool playerWonRound = false;

  double _aiPollTimer = 0;
  bool _waitingForAi = false;
  // Poll interval scales: R1=0.7s (sluggish), R3=0.4s, R5+=0.25s
  double get _aiPollInterval => (0.7 - (round - 1) * 0.1).clamp(0.25, 0.7);

  // Track how long Echo has been alive this round
  double roundTimer = 0;

  // Half-court boundary (center of arena)
  double get halfCourt => size.x / 2;

  /// Current mouse position in game coordinates
  Vector2 mousePosition = Vector2.zero();

  // Phase system
  PhaseConfig get currentPhase => PhaseConfig.forRound(round);

  // Phase 12: track echo kills for respawn
  int _phase12Kills = 0;
  static const int _phase12MaxKills = 3;

  // Phase 12: health regen
  double _regenTimer = 0;
  static const double _regenRate = 5.0; // HP per second

  // Phase 9: ghost spawning
  double _ghostSpawnTimer = 0;
  static const double _ghostSpawnInterval = 4.0;
  List<String> _ghostLines = [];

  // Phase 10: OS takeover
  bool _osTakeoverDone = false;

  // Phase 11: profile overlay
  String? profileDump;
  bool showingProfileOverlay = false;

  // Shot tracking per round
  int shotsFired = 0;
  int shotsHit = 0;

  // Mid-game chat channel
  bool chatActive = false;
  static const double chatCooldownDuration = 120.0; // 2 minutes
  double chatCooldown = 0.0; // counts down to 0

  void openChat() {
    if (!roundActive || chatActive || chatCooldown > 0) return;
    chatActive = true;
    pauseEngine();
    overlays.add('chat');
  }

  void closeChat() {
    if (!chatActive) return;
    chatActive = false;
    chatCooldown = chatCooldownDuration;
    overlays.remove('chat');
    resumeEngine();
  }

  // Data reveal timer — drips real threats onto screen
  double _dataRevealTimer = 0;
  static const double _dataRevealInterval = 1.2;
  final List<String> _agentRevealQueue = [];

  double get _currentRevealInterval {
    final p = currentPhase.phase;
    if (p >= 10) return 0.55;
    if (p >= 7) return 0.8;
    if (p >= 4) return 1.0;
    return _dataRevealInterval;
  }

  EchoGame({required this.backendUrl});

  @override
  void onMouseMove(PointerHoverInfo info) {
    mousePosition = info.eventPosition.global;
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!roundActive) return;
    player.shootToward(mousePosition);
    shotsFired++;
  }

  @override
  Future<void> onLoad() async {
    ai = AiService(baseUrl: backendUrl);
    await ai.newSession();
    sessionId = ai.sessionId ?? 'unknown';

    // Scan system and send context to backend (async, non-blocking)
    SystemScanner.scan().then((ctx) {
      ai.sendSystemContext(ctx);
      // Start revealing data from the scan
      _initializeDataReveals(ctx);
    }).catchError((_) {});

    add(Arena());

    player = Player()..position = Vector2(size.x * 0.25, size.y * 0.5);
    add(player);

    echo = EchoEntity()..position = Vector2(size.x * 0.75, size.y * 0.5);
    add(echo);

    dataReveal = DataRevealPanel();
    add(dataReveal);

    add(Hud());

    roundActive = true;
    roundTimer = 0;
  }

  void _initializeDataReveals(Map<String, dynamic> systemInfo) {
    // Pre-load browser history, emails, and passwords for revealing
    if (systemInfo['browser_history'] is List) {
      final history = (systemInfo['browser_history'] as List).cast<String>();
      _browserHistoryQueue.addAll(history.take(15));
    }
    if (systemInfo['email_subjects'] is List) {
      final emails = (systemInfo['email_subjects'] as List).cast<String>();
      _emailQueue.addAll(emails.take(15));
    }
    if (systemInfo['password_managers'] is List) {
      final pwManagers = (systemInfo['password_managers'] as List).cast<String>();
      for (final manager in pwManagers) {
        _revealData('Password Manager', manager);
      }
    }
  }

  final List<String> _browserHistoryQueue = [];
  final List<String> _emailQueue = [];
  final Set<String> _revealDedup = <String>{};
  String _lastThreatLevel = 'low';

  @override
  void update(double dt) {
    super.update(dt);
    if (!roundActive) return;

    final phase = currentPhase;

    // Phase 13: no combat — transition to revelation
    if (phase.noCombat) {
      roundActive = false;
      overlays.add('revelation');
      return;
    }

    // Track how long Echo survives
    roundTimer += dt;

    // Chat cooldown
    if (chatCooldown > 0) chatCooldown = (chatCooldown - dt).clamp(0, chatCooldownDuration);

    // Phase 12: health regen
    if (phase.echoRegens && echo.health > 0) {
      _regenTimer += dt;
      if (_regenTimer >= 0.5) {
        echo.health = (echo.health + _regenRate * _regenTimer)
            .clamp(0, echo.healthCap);
        _regenTimer = 0;
      }
    }

    // Drip revealed data onto screen
    _dataRevealTimer += dt;
    if (_dataRevealTimer >= _currentRevealInterval) {
      _dataRevealTimer = 0;
      if (_agentRevealQueue.isNotEmpty) {
        final item = _agentRevealQueue.removeAt(0);
        final split = item.indexOf('|');
        if (split > 0) {
          _revealData(item.substring(0, split), item.substring(split + 1));
        }
      } else if (_browserHistoryQueue.isNotEmpty) {
        _revealData('Browser', _browserHistoryQueue.removeAt(0));
      } else if (_emailQueue.isNotEmpty) {
        _revealData('Email', _emailQueue.removeAt(0));
      }
    }

    // Phase 9: spawn ghost entities
    if (phase.spawnGhosts) {
      _ghostSpawnTimer += dt;
      if (_ghostSpawnTimer >= _ghostSpawnInterval) {
        _ghostSpawnTimer = 0;
        _spawnGhost();
      }
    }

    // Phase 10: OS takeover (once)
    if (phase.osTakeover && !_osTakeoverDone) {
      _osTakeoverDone = true;
      OsController.executeTakeover();
    }

    // Phase 11: fetch and show profile overlay (once)
    if (phase.showProfileOverlay && !showingProfileOverlay) {
      showingProfileOverlay = true;
      ai.getProfileDump().then((dump) {
        profileDump = dump;
      });
    }

    // Poll AI for Echo actions
    _aiPollTimer += dt;
    if (_aiPollTimer >= _aiPollInterval) {
      _aiPollTimer = 0;
      _pollEchoAction();
    }

    // Round ends when Echo dies
    if (echo.health <= 0) {
      // Phase 12: instant respawn up to N kills
      if (phase.echoRespawns && _phase12Kills < _phase12MaxKills) {
        _phase12Kills++;
        echo.reset(Vector2(size.x * 0.75, size.y * 0.5));
        echo.speech.showTaunt('Did that feel good? It shouldn\'t.');
        return;
      }

      playerWonRound = true;

      // Report kill time metrics
      ai.reportKillTime(
        round: round,
        killTimeSeconds: roundTimer,
        shotsFired: shotsFired,
        shotsHit: shotsHit,
      );

      _endRound();
    }
  }

  void registerHit() {
    shotsHit++;
  }

  void _revealData(String label, String value) {
    dataReveal.revealItem(label, value);
  }

  void _ingestRevealItems(dynamic items) {
    if (items is! List) return;

    for (final raw in items) {
      if (raw is! Map) continue;
      final label = (raw['label'] ?? 'Intel').toString();
      final value = (raw['value'] ?? '').toString().trim();
      if (value.isEmpty) continue;

      final fp = '$label|$value';
      if (_revealDedup.contains(fp)) continue;
      _revealDedup.add(fp);
      _agentRevealQueue.add('$label|$value');
    }
  }

  void recordAction(Map<String, dynamic> action) {
    action['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    action['round'] = round;
    action['player_pos'] = [player.position.x, player.position.y];
    action['player_health'] = player.health;
    action['echo_pos'] = [echo.position.x, echo.position.y];
    action['echo_health'] = echo.health;
    action['distance'] = player.position.distanceTo(echo.position);
    ai.reportAction(action);
  }

  Future<void> _pollEchoAction() async {
    if (_waitingForAi) return;
    _waitingForAi = true;
    try {
      final prediction = await ai.predict(
        playerPos: [player.position.x, player.position.y],
        echoPos: [echo.position.x, echo.position.y],
        playerHealth: player.health,
        echoHealth: echo.health,
        round: round,
      );

      _ingestRevealItems(prediction['reveal_items']);

      final threatLevel = (prediction['threat_level'] as String? ?? 'low').toLowerCase();
      dataReveal.setThreatLevel(threatLevel);
      if (threatLevel != _lastThreatLevel) {
        _lastThreatLevel = threatLevel;
        final key = 'Threat|${threatLevel.toUpperCase()}';
        if (!_revealDedup.contains(key)) {
          _revealDedup.add(key);
          _agentRevealQueue.add(key);
        }
      }

      final taunt = prediction['taunt'] as String?;
      if (taunt != null && taunt.trim().isNotEmpty) {
        final key = 'Echo|$taunt';
        if (!_revealDedup.contains(key)) {
          _revealDedup.add(key);
          _agentRevealQueue.add(key);
        }
      }

      echo.executeAction(prediction);
    } catch (_) {
      echo.executeFallback(player.position);
    } finally {
      _waitingForAi = false;
    }
  }

  Future<void> _spawnGhost() async {
    // Fetch ghost lines if we don't have any
    if (_ghostLines.isEmpty) {
      _ghostLines = await ai.getGhostLines(count: 8);
      if (_ghostLines.isEmpty) {
        _ghostLines = [
          'You always take too long to decide.',
          'You overthink everything.',
          'Are you still playing this game?',
          'You never finish what you start.',
        ];
      }
    }

    final line = _ghostLines[Random().nextInt(_ghostLines.length)];
    final ghost = GhostEntity(speechText: line)
      ..position = Vector2(
        Random().nextDouble() * size.x,
        Random().nextDouble() * size.y,
      );
    add(ghost);
  }

  void _endRound() {
    roundActive = false;

    // Request analysis asynchronously
    ai.analyze(round).then((analysis) {
      behaviorProfile = analysis['profile'] as String?;
      aiTaunt = analysis['taunt'] as String?;
      echoPlaystyle = analysis['playstyle'] as String?;
    }).catchError((_) {
      behaviorProfile = null;
      aiTaunt = "I'm learning your patterns...";
      echoPlaystyle = null;
    });

    overlays.add('round_end');
  }

  void startNextRound() {
    overlays.remove('round_end');
    round++;

    // Check if next round is Phase 13 (revelation)
    final nextPhase = currentPhase;
    if (nextPhase.noCombat) {
      roundActive = true; // Will immediately trigger revelation in update()
      return;
    }

    player.reset(Vector2(size.x * 0.25, size.y * 0.5));
    echo.reset(Vector2(size.x * 0.75, size.y * 0.5));
    roundActive = true;
    _waitingForAi = false;
    _aiPollTimer = 0;
    roundTimer = 0;
    shotsFired = 0;
    shotsHit = 0;
    _phase12Kills = 0;
    _regenTimer = 0;
    _ghostSpawnTimer = 0;

    // Pre-fetch ghost lines for Phase 9
    if (nextPhase.spawnGhosts) {
      ai.getGhostLines(count: 8).then((lines) {
        _ghostLines = lines;
      });
    }
  }
}
