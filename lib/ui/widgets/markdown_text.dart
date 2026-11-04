/// 极简 Markdown 渲染：只覆盖 Release 说明里会出现的语法
/// （# 标题、- 列表、**粗体**、`代码`、[链接](url)、--- 分隔线、``` 代码块）。
///
/// 不引第三方包：一是体积，二是这里要贴合 App 自己的字号与配色。
library;

import 'package:flutter/material.dart';

class MarkdownText extends StatelessWidget {
  const MarkdownText(this.source, {super.key, this.baseStyle});

  final String source;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final base = baseStyle ??
        text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.55,
        );

    final blocks = <Widget>[];
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    var i = 0;

    while (i < lines.length) {
      final trimmed = lines[i].trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // ``` 代码块
      if (trimmed.startsWith('```')) {
        i++;
        final buf = <String>[];
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buf.add(lines[i]);
          i++;
        }
        i++;
        blocks.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              buf.join('\n'),
              style: base?.copyWith(fontFamily: 'JetBrainsMono', height: 1.45),
            ),
          ),
        );
        continue;
      }

      // --- 分隔线
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
              height: 1,
            ),
          ),
        );
        i++;
        continue;
      }

      // # 标题
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final style = switch (level) {
          1 => text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          2 => text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          3 => text.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          _ => text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        };
        blocks.add(
          Padding(
            padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 14, bottom: 2),
            child: Text.rich(_inline(heading.group(2)!, style ?? base, scheme)),
          ),
        );
        i++;
        continue;
      }

      // - 列表
      final bullet = RegExp(r'^([-*+])\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 8, left: 2),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _inline(bullet.group(2)!, base, scheme),
                  ),
                ),
              ],
            ),
          ),
        );
        i++;
        continue;
      }

      // > 引用
      if (trimmed.startsWith('>')) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: scheme.outlineVariant, width: 3),
                ),
              ),
              child: Text.rich(
                _inline(
                  trimmed.replaceFirst(RegExp(r'^>\s?'), ''),
                  base,
                  scheme,
                ),
              ),
            ),
          ),
        );
        i++;
        continue;
      }

      // 普通段落：连续非空行合并
      final buf = <String>[trimmed];
      i++;
      while (i < lines.length) {
        final next = lines[i].trim();
        if (next.isEmpty ||
            next.startsWith('#') ||
            next.startsWith('- ') ||
            next.startsWith('* ') ||
            next.startsWith('```') ||
            next.startsWith('>') ||
            RegExp(r'^(-{3,}|\*{3,})$').hasMatch(next)) {
          break;
        }
        buf.add(next);
        i++;
      }
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text.rich(_inline(buf.join(' '), base, scheme)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  /// 行内语法：`**粗体**`、`` `代码` ``、`[文字](链接)`
  TextSpan _inline(String text, TextStyle? base, ColorScheme scheme) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*)|(`[^`]+`)|(\[[^\]]+\]\([^)]+\))');
    var index = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > index) {
        spans.add(TextSpan(text: text.substring(index, m.start)));
      }
      final token = m.group(0)!;
      if (token.startsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (token.startsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              backgroundColor: scheme.surfaceContainerHigh,
              fontSize: (base?.fontSize ?? 13) - 0.5,
            ),
          ),
        );
      } else {
        final link = RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(token)!;
        spans.add(
          TextSpan(
            text: link.group(1)!,
            style: TextStyle(
              color: scheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: scheme.primary.withValues(alpha: 0.6),
            ),
          ),
        );
      }
      index = m.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return TextSpan(style: base, children: spans);
  }
}
