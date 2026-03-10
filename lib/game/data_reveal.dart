import 'dart:ui' hide TextStyle;
import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextStyle, FontWeight, TextPainter, TextDirection, TextSpan;
import 'echo_game.dart';

/// Data reveal panel — shows discovered threats stacking on the right side.
/// Appears when Echo reveals information (browser history, emails, passwords).
class DataRevealPanel extends PositionComponent with HasGameReference<EchoGame> {
  final List<String> _revealedItems = [];
  static const double maxItems = 16;
  static const double itemHeight = 18;
  static const double panelWidth = 280;
  static const double padding = 12;
  String _threatLevel = 'LOW';

  void revealItem(String label, String value) {
    final item = '$label: ${_truncate(value, 35)}';
    _revealedItems.insert(0, item);
    if (_revealedItems.length > maxItems) {
      _revealedItems.removeLast();
    }
  }

  String _truncate(String s, int len) {
    return s.length > len ? '${s.substring(0, len - 3)}...' : s;
  }

  void clear() => _revealedItems.clear();

  void setThreatLevel(String level) {
    final normalized = level.trim().toUpperCase();
    if (normalized.isNotEmpty) {
      _threatLevel = normalized;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_revealedItems.isEmpty) return;

    final Color threatColor = switch (_threatLevel) {
      'CRITICAL' => const Color(0xFFFF1744),
      'HIGH' => const Color(0xFFFF5252),
      'MEDIUM' => const Color(0xFFFF8A80),
      _ => const Color(0xFFEF9A9A),
    };

    // Semi-transparent dark background panel
    final panelRect = Rect.fromLTWH(
      game.size.x - panelWidth - 20,
      20,
      panelWidth,
      (_revealedItems.length * itemHeight) + (padding * 2),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFF0A0A0A).withAlpha(200),
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(panelRect, const Radius.circular(6)),
      Paint()
        ..color = threatColor.withAlpha(120)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Title
    final titlePaint = TextPainter(
      text: const TextSpan(
        text: 'EXPOSED',
        style: TextStyle(
          color: Color(0xFFFF1744),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    titlePaint.paint(
      canvas,
      Offset(
        panelRect.left + padding,
        panelRect.top + padding / 2,
      ),
    );

    final levelPaint = TextPainter(
      text: TextSpan(
        text: _threatLevel,
        style: TextStyle(
          color: threatColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    levelPaint.paint(
      canvas,
      Offset(
        panelRect.right - padding - levelPaint.width,
        panelRect.top + padding / 2,
      ),
    );

    // Items
    for (int i = 0; i < _revealedItems.length; i++) {
      final itemPaint = TextPainter(
        text: TextSpan(
          text: _revealedItems[i],
          style: TextStyle(
            color: const Color(0xFFFF1744).withAlpha(200 - (i * 20).clamp(0, 150)),
            fontSize: 9,
            fontFamily: 'monospace',
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: panelWidth - (padding * 2));

      itemPaint.paint(
        canvas,
        Offset(
          panelRect.left + padding,
          panelRect.top + padding + 12 + (i * itemHeight),
        ),
      );
    }
  }
}
