import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Clean multi-line progress-history chart (no extra packages).
///
/// Draws up to 4 series over the trailing calendar months. A null value
/// is a gap in the line (months with no records), never a fake zero.
class ProgressChart extends StatelessWidget {
  final List<String> monthLabels;
  final List<ChartSeries> series;
  const ProgressChart({
    super.key,
    required this.monthLabels,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    if (monthLabels.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 210,
          width: double.infinity,
          child: CustomPaint(
            painter: _ChartPainter(
              monthLabels: monthLabels,
              series: series,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 4,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.label,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class ChartSeries {
  final String label;
  final Color color;
  final List<double?> values;
  const ChartSeries({
    required this.label,
    required this.color,
    required this.values,
  });
}

class _ChartPainter extends CustomPainter {
  final List<String> monthLabels;
  final List<ChartSeries> series;
  _ChartPainter({required this.monthLabels, required this.series});

  static const _leftPad = 34.0;
  static const _rightPad = 12.0;
  static const _topPad = 12.0;
  static const _bottomPad = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - _leftPad - _rightPad;
    final plotH = size.height - _topPad - _bottomPad;
    if (plotW <= 0 || plotH <= 0) return;

    final gridPaint = Paint()
      ..color = const Color(0xFFE8EEF6)
      ..strokeWidth = 1;
    final labelStyle = GoogleFonts.poppins(
      fontSize: 10,
      color: const Color(0xFF94A3B8),
    );

    // Horizontal gridlines at 0 / 50 / 100.
    for (final pct in [0.0, 50.0, 100.0]) {
      final y = _topPad + plotH * (1 - pct / 100);
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(_leftPad + plotW, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(
            text: '${pct.toInt()}%',
            style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    final n = monthLabels.length;
    double xAt(int i) =>
        _leftPad + (n == 1 ? plotW / 2 : plotW * i / (n - 1));
    double yAt(double v) =>
        _topPad + plotH * (1 - v.clamp(0, 100) / 100);

    // Month labels.
    for (var i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(text: monthLabels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(xAt(i) - tp.width / 2, _topPad + plotH + 8),
      );
    }

    // Series lines with dots; nulls break the line (gap, not zero).
    for (final s in series) {
      final linePaint = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      Offset? prev;
      for (var i = 0; i < n && i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) {
          prev = null;
          continue;
        }
        final p = Offset(xAt(i), yAt(v));
        if (prev != null) canvas.drawLine(prev, p, linePaint);
        canvas.drawCircle(p, 4, Paint()..color = Colors.white);
        canvas.drawCircle(
            p, 4, Paint()..color = s.color..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
        canvas.drawCircle(p, 1.8, Paint()..color = s.color);
        prev = p;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.monthLabels != monthLabels || old.series != series;
}
