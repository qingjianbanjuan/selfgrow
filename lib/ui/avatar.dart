import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 主界面那个小人。
/// - [level]    综合等级，决定配色
/// - [vitality] 0..1 状态（心情/睡眠/体力的综合），低时变灰、眼神下垂
class AvatarFigure extends StatefulWidget {
  final double level;
  final double vitality;

  const AvatarFigure({super.key, required this.level, required this.vitality});

  @override
  State<AvatarFigure> createState() => _AvatarFigureState();
}

class _AvatarFigureState extends State<AvatarFigure>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return CustomPaint(
          painter: _AvatarPainter(
            level: widget.level,
            vitality: widget.vitality.clamp(0.0, 1.0),
            phase: t,
          ),
          size: const Size(200, 240),
        );
      },
    );
  }
}

class _AvatarPainter extends CustomPainter {
  final double level;
  final double vitality;
  final double phase;

  _AvatarPainter({
    required this.level,
    required this.vitality,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.58;
    final bob = (phase - 0.5) * 6.0;

    final base = levelColor(level);
    // 状态差 -> 灰化
    final body = Color.lerp(
      const Color(0xFF6B7280),
      base,
      0.35 + vitality * 0.65,
    )!;

    // ---- 背后光晕 ----
    final glowR = size.height * 0.42;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [base.withAlpha(60), base.withAlpha(0)],
      ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: glowR));
    canvas.drawCircle(Offset(cx, cy), glowR, glow);

    // ---- 影子 ----
    final shadow = Paint()..color = Colors.black.withAlpha(70);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + 96),
        width: 96,
        height: 18,
      ),
      shadow,
    );

    final dy = bob;
    final bodyPaint = Paint()..color = body;
    final bodyDark = Paint()
      ..color = Color.lerp(body, Colors.black, 0.28)!;

    // ---- 腿 ----
    final legPaint = Paint()
      ..color = bodyDark.color
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(cx - 15, cy + 26 + dy), Offset(cx - 17, cy + 58 + dy), legPaint);
    canvas.drawLine(
        Offset(cx + 15, cy + 26 + dy), Offset(cx + 17, cy + 58 + dy), legPaint);

    // ---- 身体 ----
    final torso = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(cx, cy + 2 + dy), width: 62, height: 66),
      const Radius.circular(24),
    );
    canvas.drawRRect(torso, bodyPaint);

    // ---- 手臂（随呼吸轻微摆动）----
    final armPaint = Paint()
      ..color = body
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    final swing = (phase - 0.5) * 8;
    canvas.drawLine(Offset(cx - 28, cy - 10 + dy),
        Offset(cx - 40, cy + 22 + dy + swing), armPaint);
    canvas.drawLine(Offset(cx + 28, cy - 10 + dy),
        Offset(cx + 40, cy + 22 + dy + swing), armPaint);

    // ---- 头 ----
    const headR = 34.0;
    final headCenter = Offset(cx, cy - 52 + dy);
    canvas.drawCircle(headCenter, headR, bodyPaint);

    // 头发（顶部一条弧）
    final hair = Paint()
      ..color = Color.lerp(body, Colors.black, 0.45)!
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      Rect.fromCircle(center: headCenter, radius: headR),
      math.pi * 1.05,
      math.pi * 0.9,
      true,
      hair,
    );

    // ---- 五官 ----
    final eyeY = headCenter.dy + 4;
    final eyePaint = Paint()..color = const Color(0xFF0B0E13);
    final eyeOpen = 0.35 + vitality * 0.65; // 状态差 -> 眯眼
    final eyeR = 4.2 * eyeOpen;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(headCenter.dx - 12, eyeY), width: 8, height: eyeR * 2),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(headCenter.dx + 12, eyeY), width: 8, height: eyeR * 2),
      eyePaint,
    );

    // 嘴：状态好用微笑，状态差用平线
    final mouth = Paint()
      ..color = const Color(0xFF0B0E13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final my = headCenter.dy + 20;
    if (vitality > 0.55) {
      canvas.drawArc(
        Rect.fromCenter(
            center: Offset(headCenter.dx, my - 4), width: 18, height: 12),
        0.15,
        math.pi - 0.3,
        false,
        mouth,
      );
    } else {
      canvas.drawLine(
          Offset(headCenter.dx - 8, my), Offset(headCenter.dx + 8, my), mouth);
    }
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.level != level ||
      old.vitality != vitality ||
      old.phase != phase;
}
