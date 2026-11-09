import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/voice_profile.dart';
import '../theme/app_theme.dart';

/// Biểu đồ Radar 5 cạnh hiển thị trực quan đặc trưng giọng của người dùng:
/// 1. Độ Ấm (Warmth)
/// 2. Độ Sáng (Brightness / Air)
/// 3. Nội Lực (Power / Dynamic)
/// 4. Chuẩn Cao Độ (Pitch Accuracy)
/// 5. Độ Mượt (Smoothness / Ít chói sibilance)
class RadarProfileChart extends StatelessWidget {
  final UserVoiceProfile profile;
  final double size;

  const RadarProfileChart({
    super.key,
    required this.profile,
    this.size = 210,
  });

  @override
  Widget build(BuildContext context) {
    final values = [
      profile.warmthScore,
      profile.brightnessScore,
      profile.powerScore,
      profile.pitchAccuracyScore,
      profile.smoothnessScore,
    ];
    const labels = [
      'Độ Ấm',
      'Độ Sáng',
      'Nội Lực',
      'Chuẩn Pitch',
      'Độ Mượt',
    ];

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RadarPainter(values: values, labels: labels),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  _RadarPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.34;
    final int sides = values.length;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Vẽ 4 vòng lưới ngũ giác đồng tâm
    for (int level = 1; level <= 4; level++) {
      final double r = radius * (level / 4.0);
      final path = Path();
      for (int i = 0; i < sides; i++) {
        final double angle = -math.pi / 2 + (2 * math.pi * i / sides);
        final pt = Offset(
          center.dx + r * math.cos(angle),
          center.dy + r * math.sin(angle),
        );
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Vẽ các trục từ tâm ra đỉnh và nhãn tên chỉ số
    for (int i = 0; i < sides; i++) {
      final double angle = -math.pi / 2 + (2 * math.pi * i / sides);
      final outer = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, outer, gridPaint);

      final labelOffset = Offset(
        center.dx + (radius + 24) * math.cos(angle),
        center.dy + (radius + 20) * math.sin(angle),
      );
      final percent = (values[i] * 100).round();
      final tp = TextPainter(
        text: TextSpan(
          text: '${labels[i]}\n$percent%',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(labelOffset.dx - tp.width / 2, labelOffset.dy - tp.height / 2),
      );
    }

    // Vẽ miền giá trị giọng của người dùng
    final dataPath = Path();
    final List<Offset> points = [];
    for (int i = 0; i < sides; i++) {
      final double angle = -math.pi / 2 + (2 * math.pi * i / sides);
      final double r = radius * values[i].clamp(0.15, 1.0);
      final pt = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      points.add(pt);
      if (i == 0) {
        dataPath.moveTo(pt.dx, pt.dy);
      } else {
        dataPath.lineTo(pt.dx, pt.dy);
      }
    }
    dataPath.close();

    final fillPaint = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0x8800E5FF),
          Color(0x557C4DFF),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = AppTheme.accentCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawPath(dataPath, fillPaint);
    canvas.drawPath(dataPath, strokePaint);

    // Vẽ các điểm nút
    final dotPaint = Paint()..color = Colors.white;
    for (final pt in points) {
      canvas.drawCircle(pt, 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => true;
}
