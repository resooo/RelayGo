import 'package:flutter/material.dart';

/// RelayGo 主题（Material 3 · 绿/青品牌色）
///
/// 设计稿：relaygo-design.html（Flutter / Material 3 对齐）
/// - 品牌：Primary Green #00C853 / Secondary Teal #00BFA5
/// - 渐变：#00C853 → #00BFA5（135°）
/// - 默认浅色主题（M3 Light roles），深色主题跟随系统
/// - 字体：界面 Inter，数据 JetBrains Mono（Flutter 端回退系统字体 / monospace）
/// - 圆角：8(小) / 12(中) / 16(大) / 28(特大)
class AppTheme {
  // —— 品牌色 ——
  static const Color brandGreen = Color(0xFF00C853);
  static const Color brandTeal = Color(0xFF00BFA5);
  static const Color brandDark = Color(0xFF009624);
  static const Color brandLight = Color(0xFF69F0AE);

  // —— 浅色令牌（默认）——
  static const Color bg = Color(0xFFFFFFFF);
  static const Color bg2 = Color(0xFFF7F8FA);
  static const Color surface = Color(0xFFF7F8FA);
  static const Color surface2 = Color(0xFFF0F2F5);
  static const Color surface3 = Color(0xFFE9ECEF);
  static const Color border = Color(0xFFE0E2E6);
  static const Color borderStrong = Color(0xFFC4C7CC);

  static const Color text = Color(0xFF1A1C1E);
  static const Color text2 = Color(0xFF44474E);
  static const Color text3 = Color(0xFF8A9099);

  // 强调色（品牌绿 / 青）
  static const Color accent = Color(0xFF00C853);
  static const Color accentStrong = Color(0xFF00BFA5);
  static const Color accentSoft = Color(0x1F00C853); // rgba(0,200,83,.12)
  static const Color accentLine = Color(0x5900C853); // rgba(0,200,83,.35)

  // 语义色
  static const Color success = Color(0xFF4CAF50);
  static const Color successSoft = Color(0x1F4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color warningSoft = Color(0x24FF9800);
  static const Color danger = Color(0xFFF44336);
  static const Color dangerSoft = Color(0x1FF44336);
  static const Color info = Color(0xFF2196F3);
  static const Color infoSoft = Color(0x1F2196F3);

  // —— 深色令牌（跟随系统）——
  static const Color dBg = Color(0xFF121212);
  static const Color dBg2 = Color(0xFF1A1D21);
  static const Color dSurface = Color(0xFF1E1E1E);
  static const Color dSurface2 = Color(0xFF23262B);
  static const Color dSurface3 = Color(0xFF2A2E34);
  static const Color dBorder = Color(0xFF3A3F46);
  static const Color dBorderStrong = Color(0xFF8A9099);

  static const Color dText = Color(0xFFE3E3E3);
  static const Color dText2 = Color(0xFFC4C7CE);
  static const Color dText3 = Color(0xFF7C828C);

  static const Color dAccent = Color(0xFF69F0AE);
  static const Color dAccentStrong = Color(0xFF00BFA5);
  static const Color dAccentSoft = Color(0x1F69F0AE);
  static const Color dAccentLine = Color(0x5969F0AE);

  static const Color dSuccess = Color(0xFF4CAF50);
  static const Color dWarning = Color(0xFFFFB74D);
  static const Color dDanger = Color(0xFFFFB4AB);
  static const Color dInfo = Color(0xFF64B5F6);

  // 字体
  static const String uiFontFamily = 'Inter';
  static const String monoFontFamily = 'monospace';

  // 圆角
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 28;

  /// 品牌渐变（Logo / 主按钮 / 高亮元素）
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandGreen, brandTeal],
  );

  /// 渐变按下态
  static const LinearGradient brandGradientPressed = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandDark, Color(0xFF00897B)],
  );

  /// 渐变禁用态
  static const LinearGradient brandGradientDisabled = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFBDBDBD), Color(0xFF9E9E9E)],
  );

  /// 浅色主题（默认，对应设计稿 M3 Light roles）
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: brandGreen,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFA6F5C4),
          onPrimaryContainer: Color(0xFF00210F),
          secondary: brandTeal,
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFC7EEE1),
          onSecondaryContainer: Color(0xFF00201A),
          tertiary: Color(0xFF69F0AE),
          surface: surface,
          onSurface: text,
          onSurfaceVariant: text2,
          outline: borderStrong,
          outlineVariant: border,
          error: Color(0xFFBA1A1A),
          onError: Colors.white,
          errorContainer: Color(0xFFFFDAD6),
          onErrorContainer: Color(0xFF410002),
          inverseSurface: Color(0xFF2E3133),
          scrim: Color(0x80000000),
        ),
        scaffoldBackgroundColor: bg,
        cardColor: Colors.white,
        fontFamily: uiFontFamily,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: text,
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: text,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.01,
          ),
        ),
        // 主按钮：绿/青渐变 + 圆角12 + 高48
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            backgroundColor: brandGreen,
            foregroundColor: Colors.white,
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            elevation: 2,
            shadowColor: const Color(0x4D00C853),
          ),
        ),
        // 描边按钮
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            side: const BorderSide(color: brandGreen),
            foregroundColor: brandGreen,
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        // 文字按钮
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: brandGreen,
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        // 卡片：圆角16 + 阴影 Level 1
        cardTheme: CardThemeData(
          elevation: 1,
          color: Colors.white,
          shadowColor: const Color(0x14000000),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
        ),
        // 输入框：圆角8 + 边框
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: brandGreen, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 2),
          ),
          hintStyle: const TextStyle(color: text3, fontSize: 14),
          labelStyle: const TextStyle(color: text2, fontSize: 14),
        ),
        // 开关：绿色
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.selected)
                ? Colors.white
                : text2,
          ),
          trackColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.selected)
                ? brandGreen
                : surface3,
          ),
        ),
        // 底部导航：M3 pill 指示器
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFA6F5C4),
          height: 72,
          elevation: 3,
          shadowColor: const Color(0x14000000),
          labelTextStyle: MaterialStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(MaterialState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: states.contains(MaterialState.selected)
                  ? const Color(0xFF00210F)
                  : text2,
            ),
          ),
          iconTheme: MaterialStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(MaterialState.selected)
                  ? const Color(0xFF006B3F)
                  : text2,
              size: 24,
            ),
          ),
        ),
        // 悬浮按钮：绿/青渐变
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: brandGreen,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
          ),
        ),
        // 对话框：圆角28
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXl),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
          ),
        ),
        dividerColor: border,
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: brandGreen,
          linearTrackColor: surface3,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            side: const BorderSide(color: borderStrong),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: text2,
          textColor: text,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF2E3133),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFF006B3F),
          unselectedLabelColor: text2,
          indicatorColor: brandGreen,
          dividerColor: border,
        ),
      );

  /// 深色主题（对应设计稿 M3 Dark roles）
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF69F0AE),
          onPrimary: Color(0xFF00391C),
          primaryContainer: Color(0xFF00522A),
          onPrimaryContainer: Color(0xFFA6F5C4),
          secondary: Color(0xFF00BFA5),
          onSecondary: Color(0xFF003731),
          secondaryContainer: Color(0xFF00493C),
          onSecondaryContainer: Color(0xFFC7EEE1),
          surface: dSurface,
          onSurface: dText,
          onSurfaceVariant: dText2,
          outline: dBorderStrong,
          outlineVariant: dBorder,
          error: Color(0xFFFFB4AB),
          onError: Color(0xFF690005),
          errorContainer: Color(0xFF93000A),
          onErrorContainer: Color(0xFFFFDAD6),
          inverseSurface: Color(0xFFE3E3E3),
          scrim: Color(0x80000000),
        ),
        scaffoldBackgroundColor: dBg,
        cardColor: dSurface,
        fontFamily: uiFontFamily,
        appBarTheme: const AppBarTheme(
          backgroundColor: dBg,
          foregroundColor: dText,
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: dText,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.01,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            backgroundColor: const Color(0xFF69F0AE),
            foregroundColor: const Color(0xFF00391C),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            elevation: 2,
            shadowColor: const Color(0x4D69F0AE),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
            side: const BorderSide(color: Color(0xFF69F0AE)),
            foregroundColor: const Color(0xFF69F0AE),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF69F0AE),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          color: dSurface,
          shadowColor: const Color(0x80000000),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dSurface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: dBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: dBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: Color(0xFF69F0AE), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide: const BorderSide(color: Color(0xFFFFB4AB)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            borderSide:
                const BorderSide(color: Color(0xFFFFB4AB), width: 2),
          ),
          hintStyle: const TextStyle(color: dText3, fontSize: 14),
          labelStyle: const TextStyle(color: dText2, fontSize: 14),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.selected)
                ? const Color(0xFF00391C)
                : dText2,
          ),
          trackColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.selected)
                ? const Color(0xFF69F0AE)
                : dSurface3,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: dSurface,
          indicatorColor: const Color(0xFF00522A),
          height: 72,
          elevation: 3,
          shadowColor: const Color(0x80000000),
          labelTextStyle: MaterialStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(MaterialState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: states.contains(MaterialState.selected)
                  ? const Color(0xFFA6F5C4)
                  : dText2,
            ),
          ),
          iconTheme: MaterialStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(MaterialState.selected)
                  ? const Color(0xFF69F0AE)
                  : dText2,
              size: 24,
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF69F0AE),
          foregroundColor: Color(0xFF00391C),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: dSurface2,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXl),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: dSurface2,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
          ),
        ),
        dividerColor: dBorder,
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF69F0AE),
          linearTrackColor: dSurface3,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: dSurface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
            side: const BorderSide(color: dBorderStrong),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: dText2,
          textColor: dText,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: dSurface2,
          contentTextStyle: const TextStyle(color: dText, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFF69F0AE),
          unselectedLabelColor: dText2,
          indicatorColor: Color(0xFF69F0AE),
          dividerColor: dBorder,
        ),
      );
}
