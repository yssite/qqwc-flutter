import 'package:flutter/material.dart';

import 'app.dart';
import 'app_state.dart';
import 'theme/app_theme.dart';
import 'ui/widgets/brand_mark.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 先出壳（与原生开屏同色的品牌页），把解析节点表 / 读设置挪到首帧之后，
  // 冷启动时第一帧就是底色，不会出现白闪或空窗。
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<AppState> _future = AppState.create();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _future,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state != null) return GlobalSpeedApp(state: state);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: _SplashScreen(failed: snapshot.hasError),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({this.failed = false});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C11),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 72),
            const SizedBox(height: 18),
            SizedBox(
              width: 96,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            if (failed) ...[
              const SizedBox(height: 18),
              const Text(
                '初始化失败，请重试',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
