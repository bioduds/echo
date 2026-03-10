import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'echo_game.dart';

class Arena extends PositionComponent with HasGameReference<EchoGame> {
  double _time = 0;

  @override
  Future<void> onLoad() async {
    size = game.size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    final center = Offset(w / 2, h / 2);

    // ── Deep black base ──────────────────────────────────────────────
    canvas.drawRect(
      Offset.zero & Size(w, h),
      Paint()..color = const Color(0xFF04040C),
    );

    // ── Phase-scaled red infection (radial gradient) ─────────────────
    final phase = game.round.clamp(1, 12);
    final baseAlpha = ((phase - 1) / 11 * 61).round().clamp(0, 61);
    final pulse = 0.5 + 0.5 * sin(_time * 1.8);
    final pulsedAlpha = (baseAlpha * (0.75 + 0.25 * pulse)).round().clamp(0, 255);
    if (pulsedAlpha > 0) {
      final diagRadius = sqrt(w * w + h * h) / 2;
      canvas.drawRect(
        Offset.zero & Size(w, h),
        Paint()
          ..shader = Gradient.radial(
            center,
            diagRadius,
            [Color.fromARGB(pulsedAlpha, 255, 23, 68), const Color(0x00FF1744)],
            [0.0, 1.0],
          ),
      );
    }

    // ── Grid ─────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = const Color(0x12FFFFFF)
      ..strokeWidth = 0.5;
    const gridSize = 48.0;
    for (double x = 0; x < w; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 0; y < h; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // ── Glitch lines (phase 8+) ───────────────────────────────────────
    if (phase >= 8) {
      final glitchPaint = Paint()
        ..color = const Color(0x18FF1744)
        ..strokeWidth = 1.0;
      final rng = Random((_time * 3).floor());
      final glitchCount = (phase - 7) * 2;
      for (int i = 0; i < glitchCount; i++) {
        final y = rng.nextDouble() * h;
        final x0 = rng.nextDouble() * w * 0.4;
        final x1 = x0 + rng.nextDouble() * w * 0.3;
        canvas.drawLine(Offset(x0, y), Offset(x1, y), glitchPaint);
      }
    }

    // ── Center divider ───────────────────────────────────────────────
    canvas.drawLine(
      Offset(w / 2, 0),
      Offset(w / 2, h),
      Paint()
        ..color = const Color(0x30FFFFFF)
        ..strokeWidth = 1.5,
    );

    // ── Center circle decorations ────────────────────────────────────
    canvas.drawCircle(
      center, 40,
      Paint()
        ..color = const Color(0x0AFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawCircle(
      center, 8,
      Paint()
        ..color = const Color(0x14FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // ── CRT scanlines ─────────────────────────────────────────────────
    final scanPaint = Paint()..color = const Color(0x0A000000);
    for (double y = 0; y < h; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, 1), scanPaint);
    }

    // ── Radial vignette ───────────────────────────────────────────────
    final vigR = max(w, h) * 0.75;
    canvas.drawRect(
      Offset.zero & Size(w, h),
      Paint()
        ..shader = Gradient.radial(
          center, vigR,
          const [Color(0x00000000), Color(0xCC000000)],
          [0.55, 1.0],
        ),
    );

    // ── Border ────────────────────────────────────────────────────────
    canvas.drawRect(
      Offset.zero & Size(w, h),
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
