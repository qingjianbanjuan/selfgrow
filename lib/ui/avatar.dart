import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 主界面那个小人。
/// - [level]    综合等级，决定配色
/// - [vitality] 0..1 状态（心情/睡眠/体力的综合），低时变灰、眼神下垂
///
/// 交互：
/// - 自动左右摇摆（呼吸感）
/// - 手指左右拖动 -> 自由旋转（带透视）
/// - 双击 -> 转一整圈
///
/// 内部按 200x240 的逻辑尺寸绘制，外层用 FittedBox 缩放到 [width]/[height]
class AvatarFigure extends StatefulWidget {
  final double level;
  final double vitality;
  final double width;
  final double height;

  const AvatarFigure({
    super.key,
    required this.level,
    required this.vitality,
    this.width = 200,
    this.height = 240,
  });

  @override
  State<AvatarFigure> createState() => _AvatarFigureState();
}

class _AvatarFigureState extends State<AvatarFigure>
    with TickerProviderStateMixin {
  /// 呼吸 / 摇摆
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  /// 双击转圈
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _manual += 2 * math.pi);
        _spin.reset();
      }
    });

  double _manual = 0;

  @override
  void dispose() {
    _breath.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _onDrag(DragUpdateDetails d) {
    setState(() => _manual += d.delta.dx * 0.012);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: GestureDetector(
        onHorizontalDragUpdate: _onDrag,
        onDoubleTap: () => _spin.forward(from: 0),
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breath, _spin]),
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_breath.value);
            final sway = (t - 0.5) * 0.5;
            final showcase = _spin.value * 2 * math.pi;
            final angle = _manual + sway + showcase;
            final flat = math.cos(angle).abs();

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0016)
                ..rotateY(angle),
              child: Opacity(
                opacity: (0.62 + 0.38 * flat).clamp(0.62, 1.0),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: CustomPaint(
                    painter: _AvatarPainter(
                      level: widget.level,
                      vitality: widget.vitality.clamp(0.0, 1.0),
                      phase: t,
                      flat: flat,
                    ),
                    size: const Size(200, 240),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  final double level;
  final double vitality;
  final double phase;
  final double flat;

  _AvatarPainter({
    required this.level,
    required this.vitality,
    required this.phase,
    required this.flat,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.55;
    final bob = (phase - 0.5) * 5.0;
    final dy = bob;

    // ---------------- 配色 ----------------
    final warm = levelColor(level);
    final base = Color.lerp(
      const Color(0xFF85BEF2), // 低等级：清亮的蓝
      warm,
      ((level - 1) / 6).clamp(0.0, 1.0),
    )!;
    final skin = Color.lerp(
      const Color(0xFF9CABBE),
      base,
      0.72 + vitality * 0.28,
    )!;
    final shirt = Color.lerp(skin, Colors.white, 0.08)!;
    final pants = Color.lerp(skin, Colors.black, 0.38)!;
    final hairC = Color.lerp(skin, Colors.black, 0.58)!;

    // ---------------- 光晕 ----------------
    final glowR = size.height * 0.40;
    canvas.drawCircle(
      Offset(cx, cy),
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [base.withAlpha(64), base.withAlpha(0)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: glowR)),
    );

    // ---------------- 影子 ----------------
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + 96),
        width: 92 * (0.55 + 0.45 * flat),
        height: 16,
      ),
      Paint()..color = Colors.black.withAlpha((66 * (0.4 + 0.6 * flat)).round()),
    );

    // ================= 几何基准 =================
    // 头：中心 (cx, cy-64)，半径 32  -> 底部 cy-32
    // 躯干：中心 (cx, cy+6)，60x64    -> 顶部 cy-26，底部 cy+38
    // 脖子：cy-35 .. cy-23  -> 露出 cy-32..cy-26 这 6px
    const headR = 32.0;
    final headC = Offset(cx, cy - 64 + dy);

    // ---------------- 腿 ----------------
    final legPaint = Paint()
      ..color = pants
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 13, cy + 30 + dy), Offset(cx - 14, cy + 56 + dy),
        legPaint);
    canvas.drawLine(Offset(cx + 13, cy + 30 + dy), Offset(cx + 14, cy + 56 + dy),
        legPaint);

    // ---------------- 脚 ----------------
    final footPaint = Paint()..color = Color.lerp(pants, Colors.black, 0.42)!;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx - 15, cy + 60 + dy), width: 23, height: 11),
      footPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx + 15, cy + 60 + dy), width: 23, height: 11),
      footPaint,
    );

    // ---------------- 脖子（先画，会被头/躯干压住两端）----------------
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy - 29 + dy), width: 18, height: 14),
        const Radius.circular(5),
      ),
      Paint()..color = Color.lerp(skin, Colors.black, 0.14)!,
    );

    // ---------------- 手臂（身体后面）----------------
    final armPaint = Paint()
      ..color = shirt
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    final swing = (phase - 0.5) * 7;
    canvas.drawLine(Offset(cx - 25, cy - 14 + dy),
        Offset(cx - 36, cy + 18 + dy + swing), armPaint);
    canvas.drawLine(Offset(cx + 25, cy - 14 + dy),
        Offset(cx + 36, cy + 18 + dy + swing), armPaint);

    // ---------------- 手 ----------------
    final handPaint = Paint()..color = Color.lerp(skin, Colors.black, 0.08)!;
    canvas.drawCircle(Offset(cx - 37, cy + 20 + dy + swing), 6, handPaint);
    canvas.drawCircle(Offset(cx + 37, cy + 20 + dy + swing), 6, handPaint);

    // ---------------- 躯干（渐变，不要硬色块）----------------
    final torso = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 6 + dy), width: 58, height: 64),
      const Radius.circular(20),
    );
    canvas.drawRRect(
      torso,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shirt, Color.lerp(shirt, Colors.black, 0.20)!],
        ).createShader(torso.outerRect),
    );

    // ---------------- 头 ----------------
    canvas.drawCircle(headC, headR, Paint()..color = skin);

    // ---------------- 头发 ----------------
    final hair = Paint()..color = hairC;
    canvas.drawArc(
      Rect.fromCircle(center: headC, radius: headR),
      math.pi * 1.02,
      math.pi * 0.96,
      true,
      hair,
    );
    for (final dxs in [-1.0, 1.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(headC.dx + 29 * dxs, headC.dy + 3),
              width: 7,
              height: 20),
          const Radius.circular(4),
        ),
        hair,
      );
    }

    // ---------------- 五官 ----------------
    final eyePaint = Paint()..color = const Color(0xFF14181F);
    final eyeOpen = 0.35 + vitality * 0.65;
    for (final dxs in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(headC.dx + 11 * dxs, headC.dy + 4),
            width: 7.5,
            height: 8.6 * eyeOpen),
        eyePaint,
      );
    }

    if (vitality > 0.6) {
      final blush = Paint()
        ..color = const Color(0xFFFF8A80).withAlpha((80 * vitality).round());
      canvas.drawCircle(Offset(headC.dx - 19, headC.dy + 13), 4.5, blush);
      canvas.drawCircle(Offset(headC.dx + 19, headC.dy + 13), 4.5, blush);
    }

    final mouth = Paint()
      ..color = const Color(0xFF14181F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round;
    final my = headC.dy + 19;
    if (vitality > 0.55) {
      canvas.drawArc(
        Rect.fromCenter(center: Offset(headC.dx, my - 4), width: 16, height: 11),
        0.15,
        math.pi - 0.3,
        false,
        mouth,
      );
    } else {
      canvas.drawLine(
          Offset(headC.dx - 7, my), Offset(headC.dx + 7, my), mouth);
    }
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.level != level ||
      old.vitality != vitality ||
      old.phase != phase ||
      old.flat != flat;
}
