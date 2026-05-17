import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 레어도별 시그너처 글로우 효과. MUR/SAR/AR/MA 같은 시세 정점 카드에만 적용.
/// CustomPainter로 손맛 — 균일 BoxShadow가 아닌 radial gradient + multi-layer.
/// REFACTOR_2026-05-12.md 4차-Round1 디자인 polish.
class RarityAura extends StatelessWidget {
  final String rarity;
  final Widget child;
  final double intensity; // 0.0~1.0
  final double radius;    // 글로우 반경

  const RarityAura({
    super.key,
    required this.rarity,
    required this.child,
    this.intensity = 1.0,
    this.radius = 80,
  });

  // 시그너처 효과 적용 대상 레어도만. 나머지는 child만 그대로.
  static const _premium = {'MUR', 'UR', 'SAR', 'AR', 'MA', 'BWR', 'SSR'};

  @override
  Widget build(BuildContext context) {
    if (!_premium.contains(rarity)) return child;

    final color = AppColors.rarityGlow(rarity);
    if (color == Colors.transparent) return child;

    return CustomPaint(
      painter: _RarityAuraPainter(
        color: color,
        intensity: intensity.clamp(0.0, 1.0),
        radius: radius,
      ),
      child: child,
    );
  }
}

class _RarityAuraPainter extends CustomPainter {
  final Color color;
  final double intensity;
  final double radius;

  _RarityAuraPainter({
    required this.color,
    required this.intensity,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 외곽 큰 글로우 (퍼지는 빛)
    final outer = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.35 * intensity),
          color.withValues(alpha: 0.18 * intensity),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.8));
    canvas.drawCircle(center, radius * 1.8, outer);

    // 중간 leak (더 진한 코어)
    final inner = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.55 * intensity),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.9));
    canvas.drawCircle(center, radius * 0.9, inner);
  }

  @override
  bool shouldRepaint(covariant _RarityAuraPainter old) =>
      old.color != color || old.intensity != intensity || old.radius != radius;
}

/// 차트/숫자용 mini sparkline. CustomPainter로 직접 그려서 손맛.
class MiniSparkline extends StatelessWidget {
  final List<double> values;
  final Color lineColor;
  final Color? fillColor;
  final double strokeWidth;
  final double height;
  final double? width;

  const MiniSparkline({
    super.key,
    required this.values,
    required this.lineColor,
    this.fillColor,
    this.strokeWidth = 1.6,
    this.height = 32,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height, width: width);
    return SizedBox(
      height: height,
      width: width ?? double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          lineColor: lineColor,
          fillColor: fillColor,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color? fillColor;
  final double strokeWidth;

  _SparklinePainter({
    required this.values,
    required this.lineColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;

    final dx = size.width / (values.length - 1);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final norm = (values[i] - minV) / range; // 0~1
      final y = size.height * (1 - norm);
      points.add(Offset(i * dx, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      // 부드러운 곡선 (Catmull-Rom 근사)
      final prev = points[i - 1];
      final curr = points[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);

    // fill
    if (fillColor != null) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(fillPath, Paint()..color = fillColor!);
    }

    // stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 마지막 점
    canvas.drawCircle(
      points.last,
      strokeWidth + 0.8,
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values ||
      old.lineColor != lineColor ||
      old.fillColor != fillColor;
}
