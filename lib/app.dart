import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'theme/app_theme.dart';
import 'ui/shell.dart';

class GlobalSpeedApp extends StatelessWidget {
  const GlobalSpeedApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // AppScope 必须挂在 MaterialApp 之上：Navigator 推入的路由、ModalBottomSheet
    // 都是 MaterialApp 的子节点，否则这些页面里取不到全局状态。
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Flutter 网测',
        debugShowCheckedModeBanner: false,
        // 全局固定深色主题（不再跟随系统 / 提供浅色）
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.25,
              ),
            ),
            child: child!,
          );
        },
        home: const AppShell(),
      ),
    );
  }
}

/// 通过 InheritedNotifier 暴露全局状态：任何 `AppScope.of(context)` 都会随状态刷新。
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AppScope>()
        : context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未挂载');
    return scope!.notifier!;
  }
}

/// 状态栏样式：固定深色底 + 浅色图标
class SystemBars extends StatelessWidget {
  const SystemBars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: child,
    );
  }
}
