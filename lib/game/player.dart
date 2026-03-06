import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'echo_game.dart';
import 'projectile.dart';

class Player extends CircleComponent
    with HasGameReference<EchoGame>, KeyboardHandler, CollisionCallbacks {
  static const double _kRadius = 16;
  static const double moveSpeed = 250;
  static const double dashSpeed = 600;
  static const double attackCooldown = 0.35;
  static const double dashCooldown = 1.2;
  static const double dashDuration = 0.15;
  static const double maxHealth = 100;

  double health = maxHealth;
  Vector2 velocity = Vector2.zero();
  Vector2 facing = Vector2(1, 0);

  double _attackTimer = 0;
  double _dashTimer = 0;
  double _dashActiveTimer = 0;
  bool _isDashing = false;
  double _sampleTimer = 0;
  Vector2? _lastRecordedDir;

  final Set<LogicalKeyboardKey> _keysPressed = {};

  Player() : super(radius: _kRadius, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    paint = Paint()..color = const Color(0xFF00E5FF);
    add(CircleHitbox());
  }

  @override
  void render(Canvas canvas) {
    // Glow
    canvas.drawCircle(
      Offset.zero,
      _kRadius * 2.2,
      Paint()
        ..color = const Color(0x1800E5FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    super.render(canvas);
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    _keysPressed.clear();
    _keysPressed.addAll(keysPressed);

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
          event.logicalKey == LogicalKeyboardKey.shiftRight) {
        _tryDash();
      }
    }
    return true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _attackTimer = (_attackTimer - dt).clamp(0, double.infinity);
    _dashTimer = (_dashTimer - dt).clamp(0, double.infinity);

    // Movement direction from keys
    velocity = Vector2.zero();
    if (_keysPressed.contains(LogicalKeyboardKey.keyW)) velocity.y -= 1;
    if (_keysPressed.contains(LogicalKeyboardKey.keyS)) velocity.y += 1;
    if (_keysPressed.contains(LogicalKeyboardKey.keyA)) velocity.x -= 1;
    if (_keysPressed.contains(LogicalKeyboardKey.keyD)) velocity.x += 1;
    if (velocity.length > 0) {
      velocity.normalize();
      facing = velocity.clone();
    }

    // Apply movement
    if (_isDashing) {
      _dashActiveTimer -= dt;
      if (_dashActiveTimer <= 0) _isDashing = false;
      position += facing * dashSpeed * dt;
    } else {
      position += velocity * moveSpeed * dt;
    }

    // Clamp to left half of arena (player's side)
    position.x = position.x.clamp(_kRadius, game.halfCourt - _kRadius);
    position.y = position.y.clamp(_kRadius, game.size.y - _kRadius);

    // Record actions (throttled)
    _sampleTimer += dt;
    if (_sampleTimer >= 0.2) {
      _sampleTimer = 0;
      final isMoving = velocity.length > 0;
      final dirChanged = _lastRecordedDir == null ||
          velocity.distanceTo(_lastRecordedDir!) > 0.3;
      if (isMoving && dirChanged) {
        _lastRecordedDir = velocity.clone();
        game.recordAction({
          'type': _isDashing ? 'DASH' : 'MOVE',
          'direction': [facing.x, facing.y],
        });
      } else if (!isMoving && _lastRecordedDir != null) {
        _lastRecordedDir = null;
        game.recordAction({'type': 'IDLE', 'direction': [0, 0]});
      }
    }
  }

  /// Shoot a projectile toward the given world position (mouse cursor).
  void shootToward(Vector2 target) {
    if (_attackTimer > 0) return;
    _attackTimer = attackCooldown;
    final direction = (target - position);
    if (direction.length == 0) return;
    direction.normalize();
    game.add(Projectile(
      direction: direction,
      isPlayerOwned: true,
      startPos: position.clone(),
    ));
    game.recordAction({
      'type': 'ATTACK',
      'direction': [direction.x, direction.y],
    });
  }

  void _tryDash() {
    if (_dashTimer > 0 || velocity.length == 0) return;
    _dashTimer = dashCooldown;
    _isDashing = true;
    _dashActiveTimer = dashDuration;
    game.recordAction({
      'type': 'DASH',
      'direction': [facing.x, facing.y],
    });
  }

  void takeDamage(double amount) {
    health = (health - amount).clamp(0, maxHealth);
  }

  void reset(Vector2 pos) {
    position = pos;
    health = maxHealth;
    velocity = Vector2.zero();
    _keysPressed.clear();
    _isDashing = false;
  }
}
