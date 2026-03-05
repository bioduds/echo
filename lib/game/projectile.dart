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
    final glowColor = isPlayerOwned ? const Color(0x4000E5FF) : const Color(0x40FF1744);
    canvas.drawCircle(
      Offset.zero,
      projectileRadius * 2.5,
      Paint()
        ..color = glowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    super.render(canvas);
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
