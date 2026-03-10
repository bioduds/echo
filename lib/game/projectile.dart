import 'dart:math';
import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'echo_game.dart';
import 'player.dart';
import 'echo_entity.dart';

class Projectile extends CircleComponent
    with HasGameReference<EchoGame>, CollisionCallbacks {
  final Vector2 direction;
  final bool isPlayerOwned;
  final double damageMultiplier;
  static const double speed = 420;
  static const double baseDamage = 12;
  static const double projectileRadius = 4;
  double lifetime = 2.5;

  double get damage => baseDamage * damageMultiplier;

  Projectile({
    required this.direction,
    required this.isPlayerOwned,
    required Vector2 startPos,
    this.damageMultiplier = 1.0,
  }) : super(radius: projectileRadius, position: startPos, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final color = isPlayerOwned ? const Color(0xFF00E5FF) : const Color(0xFFFF1744);
    paint = Paint()..color = color;
    add(CircleHitbox());
  }

  @override
  void render(Canvas canvas) {
    final angle = atan2(direction.y, direction.x);
    final glowColor = isPlayerOwned ? const Color(0x5000E5FF) : const Color(0x50FF1744);
    final coreColor = isPlayerOwned ? const Color(0xFF00E5FF) : const Color(0xFFFF1744);

    canvas.save();
    canvas.rotate(angle);

    // Bloom glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 22, height: 7.2),
        const Radius.circular(3.6),
      ),
      Paint()
        ..color = glowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Core capsule
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 11, height: 3.6),
        const Radius.circular(1.8),
      ),
      Paint()..color = coreColor,
    );

    canvas.restore();
  }

  @override
  void update(double dt) {
    super.update(dt);
    position += direction * speed * dt;
    lifetime -= dt;

    if (lifetime <= 0 ||
        position.x < -20 ||
        position.x > game.size.x + 20 ||
        position.y < -20 ||
        position.y > game.size.y + 20) {
      removeFromParent();
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Projectile) return;
    if (isPlayerOwned && other is EchoEntity) {
      other.takeDamage(damage);
      removeFromParent();
    } else if (!isPlayerOwned && other is Player) {
      other.takeDamage(damage);
      removeFromParent();
    }
  }
}
