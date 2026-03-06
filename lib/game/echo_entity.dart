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

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    paint = Paint()..color = const Color(0xFFFF1744);
    add(CircleHitbox());
    speech = EchoSpeech();
    add(speech);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(
      Offset.zero,
      _kRadius * 2.2,
      Paint()
        ..color = const Color(0x18FF1744)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    super.render(canvas);
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

    // Show taunt if backend sent one
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

  @override
  void update(double dt) {
    super.update(dt);
    _attackTimer = (_attackTimer - dt).clamp(0, double.infinity);
    _dodgeCooldown = (_dodgeCooldown - dt).clamp(0, double.infinity);
    _strafeAngle += dt * 3.5;

    // Dodge incoming projectiles
    _tryDodge(dt);

    position += currentVelocity * dt;
    // Clamp to right half of arena (Echo's side)
    position.x = position.x.clamp(game.halfCourt + _kRadius, game.size.x - _kRadius);
    position.y = position.y.clamp(_kRadius, game.size.y - _kRadius);
    currentVelocity *= 0.92;
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
