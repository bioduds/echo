import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'echo_game.dart';
import 'projectile.dart';

class EchoEntity extends CircleComponent
    with HasGameReference<EchoGame>, CollisionCallbacks {
  static const double _kRadius = 16;
  static const double moveSpeed = 250;
  static const double maxHealth = 100;
  static const double attackCooldown = 0.4;

  double health = maxHealth;
  Vector2 currentVelocity = Vector2.zero();
  Vector2 facing = Vector2(-1, 0);
  double _attackTimer = 0;

  EchoEntity() : super(radius: _kRadius, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    paint = Paint()..color = const Color(0xFFFF1744);
    add(CircleHitbox());
  }

  @override
  void render(Canvas canvas) {
    // Red glow
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

    if (dir != null && dir.length >= 2) {
      facing = Vector2(dir[0].toDouble(), dir[1].toDouble());
      if (facing.length > 0) facing.normalize();
    }

    switch (type) {
      case 'MOVE':
        currentVelocity = facing * moveSpeed;
      case 'ATTACK':
        _tryAttack();
        currentVelocity = Vector2.zero();
      case 'DASH':
        currentVelocity = facing * moveSpeed * 2.4;
      default:
        currentVelocity = Vector2.zero();
    }
  }

  void executeFallback(Vector2 playerPos) {
    final dir = playerPos - position;
    if (dir.length > 0) dir.normalize();
    facing = dir;

    final dist = position.distanceTo(playerPos);
    if (dist > 180) {
      currentVelocity = dir * moveSpeed;
    } else if (dist < 80) {
      currentVelocity = -dir * moveSpeed * 0.6;
    } else {
      _tryAttack();
      currentVelocity = Vector2.zero();
    }
  }

  void _tryAttack() {
    if (_attackTimer > 0) return;
    _attackTimer = attackCooldown;
    game.add(Projectile(
      direction: facing.normalized(),
      isPlayerOwned: false,
      startPos: position.clone(),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _attackTimer = (_attackTimer - dt).clamp(0, double.infinity);
    position += currentVelocity * dt;
    position.x = position.x.clamp(_kRadius, game.size.x - _kRadius);
    position.y = position.y.clamp(_kRadius, game.size.y - _kRadius);
    currentVelocity *= 0.92; // decay
  }

  void takeDamage(double amount) {
    health = (health - amount).clamp(0, maxHealth);
  }

  void reset(Vector2 pos) {
    position = pos;
    health = maxHealth;
    currentVelocity = Vector2.zero();
    facing = Vector2(-1, 0);
  }
}
