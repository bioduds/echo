import 'package:flame/events.dart';
import 'package:flame/game.dart';
import '../services/ai_service.dart';
import '../services/system_scanner.dart';
import 'player.dart';
import 'echo_entity.dart';
import 'arena.dart';
import 'hud.dart';

class EchoGame extends FlameGame
    with HasKeyboardHandlerComponents, HasCollisionDetection, TapCallbacks, MouseMovementDetector {
  final String backendUrl;

  late Player player;
  late EchoEntity echo;
  late AiService ai;

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

  EchoGame({required this.backendUrl});

  @override
  void onMouseMove(PointerHoverInfo info) {
    mousePosition = info.eventPosition.global;
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!roundActive) return;
    player.shootToward(mousePosition);
  }

  @override
  Future<void> onLoad() async {
    ai = AiService(baseUrl: backendUrl);
    await ai.newSession();

    // Scan system and send context to backend (async, non-blocking)
    SystemScanner.scan().then((ctx) => ai.sendSystemContext(ctx)).catchError((_) {});

    add(Arena());

    player = Player()..position = Vector2(size.x * 0.25, size.y * 0.5);
    add(player);

    echo = EchoEntity()..position = Vector2(size.x * 0.75, size.y * 0.5);
    add(echo);

    add(Hud());

    roundActive = true;
    roundTimer = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!roundActive) return;

    // Track how long Echo survives
    roundTimer += dt;

    // Poll AI for Echo actions
    _aiPollTimer += dt;
    if (_aiPollTimer >= _aiPollInterval) {
      _aiPollTimer = 0;
      _pollEchoAction();
    }

    // Round ends only when Echo dies — no timer, no mercy
    if (echo.health <= 0) {
      playerWonRound = true;
      _endRound();
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
      echo.executeAction(prediction);
    } catch (_) {
      echo.executeFallback(player.position);
    } finally {
      _waitingForAi = false;
    }
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
    player.reset(Vector2(size.x * 0.25, size.y * 0.5));
    echo.reset(Vector2(size.x * 0.75, size.y * 0.5));
    roundActive = true;
    _waitingForAi = false;
    _aiPollTimer = 0;
    roundTimer = 0;
  }
}
