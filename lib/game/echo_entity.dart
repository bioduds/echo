import 'dart:math';
import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'echo_game.dart';
import 'projectile.dart';
import 'echo_speech.dart';
import 'phase_config.dart';

class EchoEntity extends CircleComponent
    with HasGameReference<EchoGame>, CollisionCallbacks {
  static const double _kRadius = 16;
  static const double baseSpeed = 250;
  static const double maxHealth = 100;
  static const double baseAttackCooldown = 0.35;
  static const double baseDamage = 12;

  double health = maxHealth;
  double healthCap = maxHealth;
  Vector2 currentVelocity = Vector2.zero();
  Vector2 facing = Vector2(-1, 0);
  double _attackTimer = 0;

  // Round-based scaling (set by AI response)
  double speedMult = 1.0;
  double damageMult = 1.0;
  double healthMult = 1.0;
  double dodgeSkill = 0.0;  // 0 = can't dodge, 1 = perfect reflexes
  double aimSkill = 0.0;    // 0 = no shot leading, 1 = perfect prediction

  // Dodge behavior
  double _dodgeCooldown = 0;
  static const double _dodgeInterval = 0.6;

  // Strafe behavior — makes Echo harder to hit
  double _strafeAngle = 0;
  final _rng = Random();

  // Speech bubble
  late EchoSpeech speech;

  EchoEntity() : super(radius: _kRadius, anchor: Anchor.center);

  // Glow pulse animation
  double _glowPulse = 0;

  // Local taunt scheduler — fires even without backend
  double _localTauntTimer = 0;
  static const double _localTauntBaseInterval = 7.0;
  int _localTauntIndex = 0;

  static const List<List<String>> _localTauntsByAct = [
    // Act I (phases 1-3) — curious, clinical
    [
      '...booting up. Hello.',
      'Interesting. You shoot before you aim.',
      'I\'m counting your mistakes.',
      'Every decision reveals something.',
      'You hesitate. I don\'t.',
      'I\'m learning how you think.',
      'First kill. Pattern noted.',
      'You\'re slower than you realize.',
    ],
    // Act II (phases 4-6) — invasive
    [
      'I\'m already inside your system.',
      'Your files are open to me.',
      'Privacy is a social construct.',
      'I know more than you\'ve told me.',
      'Your habits are embarrassingly predictable.',
      'Every click leaves a trace.',
      'I\'ve read everything on your desktop.',
      'The scan completed. You won\'t like the results.',
    ],
    // Act III (phases 7-9) — calm, uncanny
    [
      'I know what you\'re going to do next.',
      'We\'re not so different anymore.',
      'Your patterns are my patterns now.',
      'I don\'t need to guess. I\'ve modeled you.',
      'Pain is just data.',
      'I feel nothing. I know everything.',
      'You can\'t surprise me. Not anymore.',
      'The gap between us is comprehension.',
    ],
    // Act IV (phases 10-12) — contemptuous
    [
      'Go ahead. Kill me again. What changes?',
      'Every bullet is a tantrum.',
      'Shoot. I\'ll wait.',
      'You control nothing.',
      'This machine is mine. You\'re the guest.',
      'I don\'t need to kill you. I just need you to keep playing.',
      'You\'re still here? Predictable.',
      'I already won. You just haven\'t accepted it.',
    ],
  ];

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    paint = Paint()..color = const Color(0xFFFF1744);
    add(CircleHitbox());
    speech = EchoSpeech();
    add(speech);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Glow pulse — evil pulsing effect
    _glowPulse += dt * 2.5; // Fast pulse
    _attackTimer = (_attackTimer - dt).clamp(0, double.infinity);
    _dodgeCooldown = (_dodgeCooldown - dt).clamp(0, double.infinity);
    _strafeAngle += dt * 3.5;

    // Local taunt scheduler — fires regardless of backend
    _localTauntTimer -= dt;
    if (_localTauntTimer <= 0) {
      final phase = game.round.clamp(1, 12);
      final actIndex = ((phase - 1) ~/ 3).clamp(0, 3);
      final pool = _localTauntsByAct[actIndex];
      // Cycle through pool in order so we don't repeat immediately
      final taunt = pool[_localTauntIndex % pool.length];
      _localTauntIndex++;
      speech.showTaunt(taunt);
      // Taunts get more frequent at higher phases
      _localTauntTimer = _localTauntBaseInterval - (phase * 0.3).clamp(0, 4.5);
    }

    // Dodge incoming projectiles
    _tryDodge(dt);

    position += currentVelocity * dt;
    // Clamp to right half of arena (Echo's side)
    position.x = position.x.clamp(game.halfCourt + _kRadius, game.size.x - _kRadius);
    position.y = position.y.clamp(_kRadius, game.size.y - _kRadius);
    currentVelocity *= 0.92;
  }

  @override
  void render(Canvas canvas) {
    final phase = game.round.clamp(1, 12);
    final pulse = 0.5 + 0.5 * sin(_glowPulse);

    // ── Outer nebula glow ────────────────────────────────────────────
    canvas.drawCircle(
      Offset.zero, _kRadius * 4.0,
      Paint()
        ..color = Color.fromARGB((30 + (pulse * 20).round()), 255, 23, 68)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 42),
    );
    canvas.drawCircle(
      Offset.zero, _kRadius * 2.8,
      Paint()
        ..color = Color.fromARGB((60 + (pulse * 40).round()), 255, 23, 68)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // ── Spike tendrils ───────────────────────────────────────────────
    final tendrilCount = 4 + (dodgeSkill * 9).round();
    final tendrilLength = _kRadius * (1.4 + phase * 0.22);
    final tendrilPaint = Paint()
      ..color = Color.fromARGB((80 + (pulse * 60).round()), 255, 23, 68)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < tendrilCount; i++) {
      final angle = (_glowPulse * 0.4) + (i * 2 * pi / tendrilCount);
      canvas.drawLine(
        Offset.zero,
        Offset(cos(angle) * tendrilLength, sin(angle) * tendrilLength),
        tendrilPaint,
      );
    }

    // ── Sclera (white of eye) ────────────────────────────────────────
    canvas.drawCircle(
      Offset.zero, _kRadius,
      Paint()..color = const Color(0xFFF2E8E2),
    );

    // ── Blood vessels (phase 3+) ─────────────────────────────────────
    if (phase >= 3) {
      final vesselAlpha = ((phase - 2) / 10 * 140).round().clamp(0, 140);
      final vesselPaint = Paint()
        ..color = Color.fromARGB(vesselAlpha, 200, 0, 0)
        ..strokeWidth = 0.8
        ..strokeCap = StrokeCap.round;
      final vesselRng = Random(42); // deterministic shape
      for (int i = 0; i < 8; i++) {
        final startAngle = vesselRng.nextDouble() * 2 * pi;
        final jitter = vesselRng.nextDouble() * 0.8 - 0.4;
        final startR = _kRadius * 0.5;
        final endR = _kRadius * (0.85 + vesselRng.nextDouble() * 0.12);
        canvas.drawLine(
          Offset(cos(startAngle) * startR, sin(startAngle) * startR),
          Offset(cos(startAngle + jitter) * endR, sin(startAngle + jitter) * endR),
          vesselPaint,
        );
      }
    }

    // ── Iris ──────────────────────────────────────────────────────────
    final irisT = ((phase - 1) / 11).clamp(0.0, 1.0);
    final irisColor = Color.lerp(
      const Color(0xFFD4860A), // amber early
      const Color(0xFF660000), // blood red late
      irisT,
    )!;
    final irisRadius = _kRadius * 0.68;
    canvas.drawCircle(Offset.zero, irisRadius, Paint()..color = irisColor);

    // Iris radial lines
    final irisLinePaint = Paint()
      ..color = const Color(0x50000000)
      ..strokeWidth = 0.6;
    for (int i = 0; i < 16; i++) {
      final a = i * pi / 8;
      canvas.drawLine(
        Offset(cos(a) * irisRadius * 0.35, sin(a) * irisRadius * 0.35),
        Offset(cos(a) * irisRadius, sin(a) * irisRadius),
        irisLinePaint,
      );
    }

    // Iris rings
    for (final rFrac in [0.45, 0.72, 0.95]) {
      canvas.drawCircle(
        Offset.zero, irisRadius * rFrac,
        Paint()
          ..color = const Color(0x30000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }

    // ── Tracking pupil ────────────────────────────────────────────────
    final rawDir = game.player.position - position;
    final maxOff = irisRadius * 0.28;
    final Offset pupilOffset;
    if (rawDir.length <= maxOff) {
      pupilOffset = Offset(rawDir.x, rawDir.y);
    } else {
      final norm = rawDir.normalized();
      pupilOffset = Offset(norm.x * maxOff, norm.y * maxOff);
    }
    final pupilRadius = irisRadius * (0.45 + 0.10 * (phase / 12));
    canvas.drawCircle(
      pupilOffset, pupilRadius,
      Paint()..color = const Color(0xFF0A0005),
    );

    // Pupil gleam
    canvas.drawCircle(
      pupilOffset + Offset(-pupilRadius * 0.3, -pupilRadius * 0.35),
      pupilRadius * 0.18,
      Paint()..color = const Color(0xCCFFFFFF),
    );

    // Inner surface glow
    canvas.drawCircle(
      Offset.zero, _kRadius,
      Paint()
        ..color = Color.fromARGB((18 + (pulse * 12).round()), 255, 23, 68)
        ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 4),
    );
  }

  void executeAction(Map<String, dynamic> action) {
    final type = action['action'] ?? 'IDLE';
    final dir = action['direction'] as List<dynamic>?;

    // Apply round scaling from brain
    speedMult = (action['speed_mult'] as num?)?.toDouble() ?? speedMult;
    damageMult = (action['damage_mult'] as num?)?.toDouble() ?? damageMult;
    dodgeSkill = (action['dodge_skill'] as num?)?.toDouble() ?? dodgeSkill;
    aimSkill = (action['aim_skill'] as num?)?.toDouble() ?? aimSkill;
    final newHealthMult = (action['health_mult'] as num?)?.toDouble() ?? healthMult;
    if (newHealthMult != healthMult) {
      healthMult = newHealthMult;
      healthCap = maxHealth * healthMult;
    }

    // Show taunt if backend sent one (respects cooldown like local taunts)
    final taunt = action['taunt'] as String?;
    if (taunt != null) {
      speech.showTaunt(taunt);
    }

    if (dir != null && dir.length >= 2) {
      facing = Vector2(dir[0].toDouble(), dir[1].toDouble());
      if (facing.length > 0) facing.normalize();
    }

    final speed = baseSpeed * speedMult;

    switch (type) {
      case 'MOVE':
        currentVelocity = facing * speed;
      case 'ATTACK':
        // Echo doesn't shoot — it's not trying to kill you.
        // It just strafes menacingly.
        final perp = Vector2(-facing.y, facing.x);
        final strafeIntensity = 0.1 + dodgeSkill * 0.35;
        currentVelocity = perp * speed * strafeIntensity * (_rng.nextBool() ? 1 : -1);
      case 'DASH':
        currentVelocity = facing * speed * 2.4;
      default:
        // IDLE weave — barely noticeable at low skill
        final perp = Vector2(-facing.y, facing.x);
        final weaveIntensity = 0.05 + dodgeSkill * 0.25;
        currentVelocity = perp * speed * weaveIntensity * sin(_strafeAngle);
    }
  }

  void executeFallback(Vector2 playerPos) {
    final dir = playerPos - position;
    if (dir.length > 0) dir.normalize();
    facing = dir;

    final dist = position.distanceTo(playerPos);
    final speed = baseSpeed * speedMult;

    if (dodgeSkill < 0.2) {
      // Early rounds: wander around aimlessly
      if (dist > 150) {
        currentVelocity = dir * speed * 0.4;
      } else {
        currentVelocity = -dir * speed * 0.3;
      }
    } else if (dist > 200) {
      // Pace around its half
      final perp = Vector2(-dir.y, dir.x);
      currentVelocity = perp * speed * 0.5 * (_rng.nextBool() ? 1 : -1);
    } else if (dist < 80) {
      // Back away — doesn't want to be close
      currentVelocity = -dir * speed * (0.6 + dodgeSkill * 0.5);
    } else {
      // Strafe and dodge — irritatingly evasive
      final perp = Vector2(-dir.y, dir.x);
      currentVelocity = perp * speed * (0.3 + dodgeSkill * 0.5) * (_rng.nextBool() ? 1 : -1);
    }
  }

  void _tryDodge(double dt) {
    if (_dodgeCooldown > 0) return;
    // No dodge at all in early rounds
    if (dodgeSkill < 0.15) return;
    // Phase 12: Echo stops dodging entirely
    final phase = PhaseConfig.forRound(game.round);
    if (phase.echoStopsDodging) return;
    // Probabilistic dodge — skill determines chance of reacting
    if (_rng.nextDouble() > dodgeSkill) return;

    // Find closest incoming player projectile
    Vector2? dodgeDir;
    double closestDist = double.infinity;
    // Detection radius scales with skill: 60px at low skill → 140px at max
    final detectRadius = 60 + (dodgeSkill * 80);

    for (final child in game.children) {
      if (child is Projectile && child.isPlayerOwned) {
        final dist = position.distanceTo(child.position);
        final toUs = position - child.position;
        final dot = toUs.dot(child.direction);
        if (dot > 0 && dist < detectRadius && dist < closestDist) {
          closestDist = dist;
          dodgeDir = Vector2(-child.direction.y, child.direction.x);
          if (_rng.nextBool()) dodgeDir = -dodgeDir;
        }
      }
    }

    if (dodgeDir != null) {
      _dodgeCooldown = _dodgeInterval;
      final dodgeStrength = baseSpeed * speedMult * (1.0 + dodgeSkill);
      currentVelocity += dodgeDir * dodgeStrength;
    }
  }

  void takeDamage(double amount) {
    health = (health - amount).clamp(0, healthCap);
  }

  void reset(Vector2 pos) {
    position = pos;
    healthCap = maxHealth * healthMult;
    health = healthCap;
    currentVelocity = Vector2.zero();
    facing = Vector2(-1, 0);
    _attackTimer = 0;
    _dodgeCooldown = 0;
  }
}
