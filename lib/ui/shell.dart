import 'package:flutter/material.dart';

import '../app.dart';
import 'pages/diagnostics_page.dart';
import 'pages/history_page.dart';
import 'pages/nodes_page.dart';
import 'pages/settings_page.dart';
import 'pages/speed_page.dart';
import 'permission_sheet.dart';
import 'widgets/bottom_bar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askPermissionsOnce());
  }

  /// 首次启动弹一次权限说明；已授权或已问过就不再打扰。
  Future<void> _askPermissionsOnce() async {
    if (!mounted) return;
    final state = AppScope.of(context, listen: false);
    if (state.settings.permissionsAsked || state.permissions.any) return;
    await state.updateSettings((s) => s.permissionsAsked = true);
    if (!mounted) return;
    await requestWithSheet(context);
  }

  void _go(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pages = <Widget>[
      SpeedPage(onOpenNodes: () => _go(3), onOpenNetwork: () => _go(2)),
      const HistoryPage(),
      const DiagnosticsPage(),
      NodesPage(onStartTest: () => _go(0)),
      const SettingsPage(),
    ];

    return SystemBars(
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: Stack(
          children: [
            // 背景：顶部极淡的主色晕染，营造层次而不喧宾夺主
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.55),
                    radius: 1.1,
                    colors: [
                      Color.alphaBlend(
                        scheme.primary.withValues(alpha: 0.10),
                        scheme.surface,
                      ),
                      scheme.surface,
                    ],
                    stops: const [0, 0.75],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: IndexedStack(index: _index, children: pages),
            ),
            // 底部导航悬浮在内容之上：内容从胶囊和手势条下面透出来，
            // 再用一层由下往上的渐隐遮罩保证可读性。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _FloatingBar(
                index: _index,
                onTap: _go,
                surface: scheme.surface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingBar extends StatelessWidget {
  const _FloatingBar({
    required this.index,
    required this.onTap,
    required this.surface,
  });

  final int index;
  final ValueChanged<int> onTap;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // 由下往上的渐隐遮罩：顶部完全透明，内容可以从胶囊下面透出来，
      // 越靠近手势条越接近底色，滚动时读起来不糊。
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            surface.withValues(alpha: 0),
            surface.withValues(alpha: 0.38),
            surface.withValues(alpha: 0.88),
          ],
          stops: const [0, 0.34, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 2),
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AppBottomBar(
              index: index,
              onTap: onTap,
              items: const [
                BottomBarItem(
                  icon: Icons.speed_outlined,
                  activeIcon: Icons.speed_rounded,
                  label: '测速',
                ),
                BottomBarItem(
                  icon: Icons.history_outlined,
                  activeIcon: Icons.history_rounded,
                  label: '记录',
                ),
                BottomBarItem(
                  icon: Icons.monitor_heart_outlined,
                  activeIcon: Icons.monitor_heart_rounded,
                  label: '诊断',
                ),
                BottomBarItem(
                  icon: Icons.hub_outlined,
                  activeIcon: Icons.hub_rounded,
                  label: '节点',
                ),
                BottomBarItem(
                  icon: Icons.tune_outlined,
                  activeIcon: Icons.tune_rounded,
                  label: '设置',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
