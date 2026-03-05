import 'dart:ui';
import 'package:flame/components.dart';

class Arena extends PositionComponent {
  @override
  Future<void> onLoad() async {
    size = findGame()!.size;
  }

  @override
  void render(Canvas canvas) {
    // Grid
    final gridPaint = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.x; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.y), gridPaint);
    }
    for (double y = 0; y < size.y; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.x, y), gridPaint);
    }

    // Border
    final borderPaint = Paint()
      ..color = const Color(0x30FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Offset.zero & Size(size.x, size.y), borderPaint);

    // Center line — half-court divider
    final centerPaint = Paint()
      ..color = const Color(0x30FFFFFF)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(size.x / 2, 0),
      Offset(size.x / 2, size.y),
      centerPaint,
    );

    // Subtle side tints
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x / 2, size.y),
      Paint()..color = const Color(0x0600E5FF),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.x / 2, 0, size.x / 2, size.y),
      Paint()..color = const Color(0x06FF1744),
    );
  }
}
