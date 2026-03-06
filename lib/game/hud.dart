import 'dart:ui' hide TextStyle;
import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle;
import 'echo_game.dart';
import 'player.dart';
import 'echo_entity.dart';
import 'phase_config.dart';

class Hud extends PositionComponent with HasGameReference<EchoGame> {
  @override
  void render(Canvas canvas) {
    final phase = PhaseConfig.forRound(game.round);

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

    // Act name (top-left below health)
    final actText = TextPaint(
      style: const TextStyle(
        color: Color(0x60FF1744),
        fontSize: 11,
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
      ),
    );
    actText.render(
      canvas,
      'ACT ${phase.act}: ${phase.actName}',
      Vector2(20, 56),
    );

    // Round counter + phase name (center)
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

    // Phase name below round
    final phaseText = TextPaint(
      style: const TextStyle(
        color: Color(0x50FFFFFF),
        fontSize: 10,
        fontFamily: 'monospace',
      ),
    );
    phaseText.render(
      canvas,
      phase.phaseName.toUpperCase(),
      Vector2(game.size.x / 2 - 50, 34),
    );

    // Survival time
    final alive = game.roundTimer;
    final aliveColor = alive > 30
        ? const Color(0xFFFF1744)
        : alive > 15
            ? const Color(0xFFFFAB00)
            : const Color(0x60FFFFFF);
    final aliveText = TextPaint(
      style: TextStyle(
        color: aliveColor,
        fontSize: 12,
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
      ),
    );
    aliveText.render(
      canvas,
      '${alive.toStringAsFixed(1)}s alive',
      Vector2(game.size.x / 2 - 35, 48),
    );

    // Phase 11: profile overlay indicator
    if (phase.showProfileOverlay && game.showingProfileOverlay) {
      final overlayText = TextPaint(
        style: const TextStyle(
          color: Color(0xA0FF1744),
          fontSize: 9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      );
      overlayText.render(
        canvas,
        '⚠ PROFILE EXPOSED',
        Vector2(game.size.x / 2 - 50, game.size.y - 30),
      );
    }
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
