import 'package:flutter/material.dart';

import 'pages/home_shell.dart';

/// 卡通高对比主题：奶油底、粗描边贴纸卡片、糖果色、大字加粗。
/// 面向教室投影设计：深墨色文字配亮色块，后排也看得清。
class ClassManagerApp extends StatelessWidget {
  const ClassManagerApp({super.key});

  static const Color ink = Color(0xFF2B2422);
  static const Color cream = Color(0xFFFFF6E5);
  static const Color red = Color(0xFFF94144);
  static const Color yellow = Color(0xFFFFD166);
  static const Color green = Color(0xFF06D6A0);
  static const Color blue = Color(0xFF118AB2);
  static const Color purple = Color(0xFF9B5DE5);
  static const Color pink = Color(0xFFFF70A6);
  static const Color orange = Color(0xFFFF9E00);

  /// 卡片糖果色轮换（名单/红花卡片按序取色，课堂氛围+区分度高）。
  static const List<Color> candyColors = [red, orange, green, blue, purple, pink];

  @override
  Widget build(BuildContext context) {
    const side = BorderSide(color: ink, width: 2.5);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: side,
    );

    final scheme = ColorScheme.light(
      primary: red,
      onPrimary: Colors.white,
      secondary: yellow,
      onSecondary: ink,
      secondaryContainer: yellow,
      onSecondaryContainer: ink,
      surface: Colors.white,
      onSurface: ink,
      onSurfaceVariant: ink,
      surfaceContainerHighest: Colors.white,
      error: red,
    );

    return MaterialApp(
      title: '小学班级管理系统',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: cream,
        fontFamily: 'KuaiLe',
        splashFactory: InkSparkle.splashFactory,
        textTheme: theme(),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: shape,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          shape: shape,
          titleTextStyle: const TextStyle(
            fontFamily: 'KuaiLe',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: ink,
          ),
          contentTextStyle: const TextStyle(
            fontFamily: 'KuaiLe',
            fontSize: 17,
            color: ink,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            side: const BorderSide(color: ink, width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(
              fontFamily: 'KuaiLe',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            side: const BorderSide(color: ink, width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(
              fontFamily: 'KuaiLe',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            side: WidgetStatePropertyAll(const BorderSide(color: ink, width: 2)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontFamily: 'KuaiLe', fontWeight: FontWeight.bold),
            ),
            foregroundColor: const WidgetStatePropertyAll(ink),
            backgroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          selectedIcon: const Icon(Icons.check_circle, color: ink),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ink, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: ink, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: red, width: 2.5),
          ),
          labelStyle: const TextStyle(fontFamily: 'KuaiLe', color: ink),
          hintStyle: TextStyle(
            fontFamily: 'KuaiLe',
            color: ink.withValues(alpha: 0.45),
          ),
        ),
        checkboxTheme: CheckboxThemeData(
          side: const BorderSide(color: ink, width: 2),
          fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? red : null,
          ),
        ),
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? red : ink,
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          side: const BorderSide(color: ink, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          labelStyle: const TextStyle(fontFamily: 'KuaiLe', color: ink),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: red),
        dividerTheme: const DividerThemeData(color: Color(0xFFE8DCC8), thickness: 1.5),
        sliderTheme: const SliderThemeData(
          activeTrackColor: red,
          inactiveTrackColor: Color(0xFFF0E4CC),
          thumbColor: red,
          overlayColor: Color(0x33F94144),
          valueIndicatorColor: ink,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : ink,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? green : Color(0xFFE8DCC8),
          ),
          trackOutlineColor: const WidgetStatePropertyAll(ink),
        ),
      ),
      home: const HomeShell(),
    );
  }

  static TextTheme theme() {
    const ink = Color(0xFF2B2422);
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'KuaiLe',
        color: ink,
        fontWeight: FontWeight.bold,
      ),
      displayMedium: TextStyle(
        fontFamily: 'KuaiLe',
        color: ink,
        fontWeight: FontWeight.bold,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'KuaiLe',
        color: ink,
        fontWeight: FontWeight.bold,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'KuaiLe',
        color: ink,
        fontWeight: FontWeight.bold,
      ),
      titleLarge: TextStyle(
        fontFamily: 'KuaiLe',
        fontSize: 26,
        color: ink,
        fontWeight: FontWeight.bold,
      ),
      titleMedium: TextStyle(fontFamily: 'KuaiLe', fontSize: 17, color: ink),
      titleSmall: TextStyle(fontFamily: 'KuaiLe', fontSize: 15, color: ink),
      bodyLarge: TextStyle(fontFamily: 'KuaiLe', color: ink),
      bodyMedium: TextStyle(fontFamily: 'KuaiLe', fontSize: 15, color: ink),
      bodySmall: TextStyle(
        fontFamily: 'KuaiLe',
        fontSize: 13,
        color: Color(0xFF6B5E52),
      ),
      labelLarge: TextStyle(fontFamily: 'KuaiLe', color: ink),
      labelMedium: TextStyle(fontFamily: 'KuaiLe', color: ink),
      labelSmall: TextStyle(fontFamily: 'KuaiLe', color: ink),
    );
  }
}
