import 'dart:ui' hide TextStyle;
import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight, TextPainter, TextDirection, TextSpan;
import 'echo_entity.dart';

/// Floating speech bubble that follows the Echo entity.
/// Shows taunts that fade in, linger, and fade out.
class EchoSpeech extends PositionComponent with ParentIsA<EchoEntity> {
  String? _currentText;
  double _timer = 0;
  double _alpha = 0;

  // Timing
  static const double fadeInDuration = 0.25;
  static const double displayDuration = 2.0;
  static const double fadeOutDuration = 0.6;
  static const double totalDuration =
      fadeInDuration + displayDuration + fadeOutDuration;

  // Cooldown so taunts don't spam
  double _cooldown = 0;
  static const double minCooldown = 2.5;

  void showTaunt(String text) {
    if (_cooldown > 0) return;
    if (text == _currentText && _timer > 0) return;
    _currentText = text;
    _timer = totalDuration;
    _cooldown = totalDuration + minCooldown;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _cooldown = (_cooldown - dt).clamp(0, double.infinity);

    if (_timer <= 0) {
      _alpha = 0;
      _currentText = null;
      return;
    }

    _timer -= dt;
    final elapsed = totalDuration - _timer;

    if (elapsed < fadeInDuration) {
      _alpha = (elapsed / fadeInDuration).clamp(0, 1);
    } else if (_timer > fadeOutDuration) {
      _alpha = 1.0;
    } else {
      _alpha = (_timer / fadeOutDuration).clamp(0, 1);
    }
  }

  @override
  void render(Canvas canvas) {
    if (_currentText == null || _alpha <= 0) return;

    final text = _currentText!;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Color.fromRGBO(255, 23, 68, _alpha),
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);

    // Position above echo, centered
    final dx = -textPainter.width / 2;
    final dy = -40.0;

    // Semi-transparent background pill
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        dx - 6,
        dy - 3,
        textPainter.width + 12,
        textPainter.height + 6,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      bgRect,
      Paint()..color = Color.fromRGBO(0, 0, 0, 0.55 * _alpha),
    );

    // Subtle glow
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = Color.fromRGBO(255, 23, 68, 0.08 * _alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    textPainter.paint(canvas, Offset(dx, dy));
  }
}
