import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globalspeed_mobile/engine/models.dart';
import 'package:globalspeed_mobile/theme/app_theme.dart';
import 'package:globalspeed_mobile/ui/widgets/needle_gauge.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('仪表盘暴露可读语义标签与数值', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const NeedleGauge(
          value: 123.4,
          maxValue: 500,
          phase: TestPhase.download,
          label: '下行速率',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    final node = tester.getSemantics(find.byType(NeedleGauge));
    expect(node.label, contains('速度仪表盘'));
    expect(node.label, contains('下行速率'));
    expect(node.value, contains('123.4'));

    handle.dispose();
  });

  testWidgets('待机时仪表盘语义值为待机', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const NeedleGauge(
          value: 0,
          maxValue: 100,
          phase: TestPhase.idle,
          label: '',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    final node = tester.getSemantics(find.byType(NeedleGauge));
    expect(node.value, '待机');

    handle.dispose();
  });
}
