import 'package:flutter/material.dart';

/// Minimal three-line live chart (X red, Y green, Z blue), no dependencies.
class SensorChart extends StatelessWidget {
  const SensorChart({
    super.key,
    required this.title,
    required this.x,
    required this.y,
    required this.z,
    required this.maxAbs,
    required this.window,
  });

  final String title;
  final List<double> x, y, z;
  final double maxAbs;
  final int window;

  static const _colors = [Colors.redAccent, Colors.green, Colors.blueAccent];

  @override
  Widget build(BuildContext context) {
    final grid = Theme.of(context).colorScheme.outlineVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleMedium)),
                for (var i = 0; i < 3; i++) ...[
                  Icon(Icons.circle, size: 10, color: _colors[i]),
                  const SizedBox(width: 4),
                  Text(['X', 'Y', 'Z'][i]),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              width: double.infinity,
              child: CustomPaint(
                painter: _ChartPainter(
                  series: [x, y, z],
                  colors: _colors,
                  maxAbs: maxAbs,
                  window: window,
                  gridColor: grid,
                ),
              ),
            ),
            Text('±${maxAbs.toStringAsFixed(maxAbs < 10 ? 1 : 0)} full scale',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.series,
    required this.colors,
    required this.maxAbs,
    required this.window,
    required this.gridColor,
  });

  final List<List<double>> series;
  final List<Color> colors;
  final double maxAbs;
  final int window;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final yy = size.height * f;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), grid);
    }

    for (var s = 0; s < series.length; s++) {
      final data = series[s];
      if (data.length < 2) continue;
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final xx = size.width - (data.length - 1 - i) * size.width / (window - 1);
        final v = data[i].clamp(-maxAbs, maxAbs).toDouble();
        final yy = size.height / 2 - (v / maxAbs) * (size.height / 2);
        if (i == 0) {
          path.moveTo(xx, yy);
        } else {
          path.lineTo(xx, yy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[s]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
