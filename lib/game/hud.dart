import 'dart:ui' hide TextStyle;
import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle;
import 'echo_game.dart';
import 'player.dart';
import 'echo_entity.dart';

class Hud extends PositionComponent with HasGameReference<EchoGame> {
  @override
  void render(Canvas canvas) {
    _drawHealthBar(
      canvas,
      20,
      20,
      game.player.health,
      Player.maxHealth,
      const Color(0xFF00E5FF),
      'YOU',
    );
    _drawHealthBar(
      canvas,
      game.size.x - 220,
      20,
      game.echo.health,
      EchoEntity.maxHealth,
      const Color(0xFFFF1744),
      'ECHO',
    );

    // Round counter
    final roundText = TextPaint(
      style: const TextStyle(
        color: Color(0x80FFFFFF),
        fontSize: 14,
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
      ),
    );
    roundText.render(
      canvas,
      'ROUND ${game.round}',
      Vector2(game.size.x / 2 - 40, 16),
    );
  }

  void _drawHealthBar(
    Canvas canvas,
    double x,
    double y,
    double health,
    double maxHealth,
    Color color,
    String label,
  ) {
    const width = 200.0;
    const height = 14.0;
    final pct = (health / maxHealth).clamp(0.0, 1.0);

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0x25FFFFFF),
    );

    // Fill
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width * pct, height),
        const Radius.circular(4),
      ),
      Paint()..color = color,
    );

    // Label
    final labelPaint = TextPaint(
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
      ),
    );
    labelPaint.render(canvas, label, Vector2(x, y + height + 4));
  }
}
