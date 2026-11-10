import 'package:flutter/material.dart';

// ---- 调色板 ----
const kBg = Color(0xFF0C0F14);
const kSurface = Color(0xFF151A21);
const kSurface2 = Color(0xFF1C232C);
const kText = Color(0xFFE6EDF3);
const kSub = Color(0xFF8B949E);
const kAccent = Color(0xFF6E8BFF);
const kUp = Color(0xFF3FB950);
const kDown = Color(0xFFF85149);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: base.colorScheme.copyWith(
      primary: kAccent,
      surface: kSurface,
      onSurface: kText,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: kText,
      displayColor: kText,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kSurface2,
      contentTextStyle: TextStyle(color: kText),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      hintStyle: const TextStyle(color: kSub),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

/// 等级 -> 颜色（越低越冷，越高越暖）
Color levelColor(double level) {
  final t = ((level - 1) / 8).clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFF5B6B85), const Color(0xFFFFC66D), t)!;
}

/// 尺寸自适应的小工具
double sp(BuildContext c, double v) =>
    v * (MediaQuery.sizeOf(c).width / 390).clamp(0.85, 1.25);
