import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight, TextPainter, TextDirection, TextSpan;
import 'echo_game.dart';

/// Ghost NPC — small translucent circle with floating speech.
/// Spawned during Phase 9 (Ghost Voices). Drifts across the arena.
/// Doesn't attack or collide — purely psychological.
class GhostEntity extends PositionComponent with HasGameReference<EchoGame> {
  static const double _kRadius = 10;
  static final _rng = Random();

  final String speechText;
  final double lifetime;
  double _elapsed = 0;
  double _speechAlpha = 0;
  late Vector2 _velocity;

  GhostEntity({
    required this.speechText,
    this.lifetime = 8.0,
  }) : super(anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Random slow drift direction
    final angle = _rng.nextDouble() * 2 * pi;
    final speed = 20 + _rng.nextDouble() * 40;
    _velocity = Vector2(cos(angle), sin(angle)) * speed;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;

    // Fade in first 1s, stay, fade out last 2s
    if (_elapsed < 1.0) {
      _speechAlpha = (_elapsed / 1.0).clamp(0, 1);
    } else if (_elapsed > lifetime - 2.0) {
      _speechAlpha = ((lifetime - _elapsed) / 2.0).clamp(0, 1);
    } else {
      _speechAlpha = 1.0;
    }

    // Drift
    position += _velocity * dt;

    // Wrap around arena
    if (position.x < -50) position.x = game.size.x + 50;
    if (position.x > game.size.x + 50) position.x = -50;
    if (position.y < -50) position.y = game.size.y + 50;
    if (position.y > game.size.y + 50) position.y = -50;

    // Remove when expired
    if (_elapsed >= lifetime) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    if (_speechAlpha <= 0) return;

    // Ghost circle — translucent, pulsing
    final pulse = 0.15 + 0.1 * sin(_elapsed * 3);
    canvas.drawCircle(
      Offset.zero,
      _kRadius * 1.8,
      Paint()
        ..color = Color.fromRGBO(255, 100, 100, pulse * _speechAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      Offset.zero,
      _kRadius,
      Paint()..color = Color.fromRGBO(255, 60, 60, 0.25 * _speechAlpha),
    );

    // Speech text above ghost
    final textPainter = TextPainter(
      text: TextSpan(
        text: speechText,
        style: TextStyle(
          color: Color.fromRGBO(255, 180, 180, 0.7 * _speechAlpha),
          fontSize: 10,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 160);

    final dx = -textPainter.width / 2;
    final dy = -_kRadius - 20;

    // Background pill
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(dx - 4, dy - 2, textPainter.width + 8, textPainter.height + 4),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      bgRect,
      Paint()..color = Color.fromRGBO(0, 0, 0, 0.4 * _speechAlpha),
    );

    textPainter.paint(canvas, Offset(dx, dy));
  }
}
