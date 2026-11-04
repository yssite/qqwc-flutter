/// Material 3 Expressive 设计系统：配色、形状、排版与弹簧动效。
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 全局动效 token（对齐 M3 Expressive 的 spatial / effects 时长）
class AppFonts {
  AppFonts._();

  /// 等宽科技感字体：仪表/读数专用
  static const String mono = 'JetBrainsMono';

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];
}

class AppMotion {
  AppMotion._();

  /// 主弹簧：位移、缩放
  static const SpringCurve spring = SpringCurve(stiffness: 340, damping: 26);
  static const SpringCurve springSoft = SpringCurve(stiffness: 220, damping: 24);
  static const SpringCurve springFast = SpringCurve(stiffness: 520, damping: 32);

  static const Duration short = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration long = Duration(milliseconds: 520);
  static const Duration page = Duration(milliseconds: 420);
}

/// 用 [SpringSimulation] 实现的非线性曲线，避免出现生硬的线性收尾。
class SpringCurve extends Curve {
  const SpringCurve({
    this.stiffness = 380,
    this.damping = 28,
    this.mass = 1,
    this.seconds = 0.75,
  });

  final double stiffness;
  final double damping;
  final double mass;
  final double seconds;

  @override
  double transformInternal(double t) {
    final simulation = SpringSimulation(
      SpringDescription(mass: mass, stiffness: stiffness, damping: damping),
      0,
      1,
      0,
    );
    final value = simulation.x(t * seconds);
    return value.isFinite ? value : 1;
  }
}

/// 主题扩展：品牌渐变与图表配色
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.downloadGradient,
    required this.uploadGradient,
    required this.gaugeGlow,
    required this.chartGrid,
    required this.success,
    required this.warning,
    required this.cardSurface,
  });

  final List<Color> downloadGradient;
  final List<Color> uploadGradient;
  final Color gaugeGlow;
  final Color chartGrid;
  final Color success;
  final Color warning;
  final Color cardSurface;

  static const dark = AppPalette(
    downloadGradient: [Color(0xFF7E97FF), Color(0xFF38D9F0)],
    uploadGradient: [Color(0xFFB49CFF), Color(0xFFF07FC7)],
    gaugeGlow: Color(0x667C93FF),
    chartGrid: Color(0x14FFFFFF),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFFB74D),
    cardSurface: Color(0xFF171A21),
  );

  @override
  AppPalette copyWith({
    List<Color>? downloadGradient,
    List<Color>? uploadGradient,
    Color? gaugeGlow,
    Color? chartGrid,
    Color? success,
    Color? warning,
    Color? cardSurface,
  }) {
    return AppPalette(
      downloadGradient: downloadGradient ?? this.downloadGradient,
      uploadGradient: uploadGradient ?? this.uploadGradient,
      gaugeGlow: gaugeGlow ?? this.gaugeGlow,
      chartGrid: chartGrid ?? this.chartGrid,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      cardSurface: cardSurface ?? this.cardSurface,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      downloadGradient: _lerpColors(downloadGradient, other.downloadGradient, t),
      uploadGradient: _lerpColors(uploadGradient, other.uploadGradient, t),
      gaugeGlow: Color.lerp(gaugeGlow, other.gaugeGlow, t)!,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
    );
  }

  static List<Color> _lerpColors(List<Color> a, List<Color> b, double t) {
    final n = a.length < b.length ? a.length : b.length;
    return List.generate(n, (i) => Color.lerp(a[i], b[i], t)!);
  }
}

extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF4C6FFF);

  /// 全局固定深色：测速场景下深色更少干扰、更有仪表感，因此不再提供浅色主题。
  static ThemeData dark() => _build();

  static ThemeData _build() {
    // fidelity 保留种子色相（品牌蓝）；expressive 的 240° 色相旋转会把蓝色变成绿色。
    // 表面色再做一层手工校正：深色更接近「墨蓝黑」，避免灰调发脏。
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final scheme = generated.copyWith(
      surface: const Color(0xFF0A0C11),
      surfaceContainerLowest: const Color(0xFF07090D),
      surfaceContainerLow: const Color(0xFF10131A),
      surfaceContainer: const Color(0xFF141821),
      surfaceContainerHigh: const Color(0xFF191E28),
      surfaceContainerHighest: const Color(0xFF202634),
      outlineVariant: const Color(0xFF2A3140),
    );
    const palette = AppPalette.dark;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = base.textTheme
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          fontFamilyFallback: const [
            'HarmonyOS Sans SC',
            'Noto Sans CJK SC',
            'Source Han Sans SC',
            'Microsoft YaHei',
            'PingFang SC',
          ],
        )
        .copyWith(
          displayLarge: base.textTheme.displayLarge?.copyWith(
            fontSize: 64,
            fontWeight: FontWeight.w700,
            letterSpacing: -2,
            height: 1.02,
          ),
          displayMedium: base.textTheme.displayMedium?.copyWith(
            fontSize: 44,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.4,
            height: 1.05,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.6,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.4,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      extensions: [palette],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _ExpressivePageTransitionsBuilder(),
          TargetPlatform.iOS: _ExpressivePageTransitionsBuilder(),
          TargetPlatform.windows: _ExpressivePageTransitionsBuilder(),
          TargetPlatform.macOS: _ExpressivePageTransitionsBuilder(),
          TargetPlatform.linux: _ExpressivePageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          shape: const StadiumBorder(),
          textStyle: textTheme.titleMedium,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        labelStyle: textTheme.labelLarge,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        showDragHandle: true,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

/// 页面切换：淡入 + 轻微放大上移，曲线用弹簧
class _ExpressivePageTransitionsBuilder extends PageTransitionsBuilder {
  const _ExpressivePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.springSoft,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Interval(0, 0.7)),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
