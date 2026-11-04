import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globalspeed_mobile/ui/widgets/markdown_text.dart';

void main() {
  const sample = '''
## Flutter 网测 v1.3.1

### 记录列表直接看出当时的网络

每行加了两个紧凑胶囊：**运营商** + **制式频段**（例如 `移动` `5G n41`）。

- 胶囊样式与详情页一致
- 时间改为 `MM-DD HH:mm` 紧凑格式

---

### 安装包
''';

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('标题不会残留 ## 符号，粗体与行内代码可渲染', (tester) async {
    await tester.pumpWidget(host(const MarkdownText(sample)));

    // 标题被解析：不再出现原始 ##
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('Flutter 网测 v1.3.1'), findsOneWidget);
    expect(find.textContaining('记录列表直接看出当时的网络'), findsOneWidget);

    // 段落里的 **粗体** 与 `代码` 标记被吃掉
    final paragraph = tester.widgetList<RichText>(find.byType(RichText)).map(
          (w) => w.text.toPlainText(),
        );
    expect(
      paragraph.any((t) => t.contains('运营商 + 制式频段') && !t.contains('**')),
      isTrue,
      reason: '粗体标记应被解析',
    );
    expect(
      paragraph.any((t) => t.contains('MM-DD HH:mm') && !t.contains('`')),
      isTrue,
      reason: '行内代码标记应被解析',
    );
  });

  testWidgets('列表项逐条渲染且去掉 - 前缀', (tester) async {
    await tester.pumpWidget(host(const MarkdownText(sample)));
    final plain = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .toList();
    expect(plain.any((t) => t.startsWith('胶囊样式与详情页一致')), isTrue);
    expect(plain.any((t) => t.startsWith('- ')), isFalse);
  });

  testWidgets('分隔线与空输入都不崩', (tester) async {
    await tester.pumpWidget(host(const MarkdownText('---')));
    expect(find.byType(Divider), findsOneWidget);

    await tester.pumpWidget(host(const MarkdownText('')));
    expect(tester.takeException(), isNull);
  });
}
