import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app.dart';
import '../../app_state.dart';
import '../../engine/models.dart';
import '../../theme/app_theme.dart';
import '../result_sheet.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/common.dart';
import '../widgets/net_tag.dart';
import '../widgets/score_ring.dart';
import '../widgets/sparkline.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final records = state.history;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: PageHeader(
            title: '测速记录',
            subtitle: records.isEmpty ? '还没有记录' : '共 ${records.length} 条 · 仅保存在本机',
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onSelected: (value) async {
                if (value == 'export') {
                  await _export(context, state);
                } else if (value == 'clear') {
                  await _clear(context, state);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'export', child: Text('导出 CSV')),
                PopupMenuItem(value: 'clear', child: Text('清空记录')),
              ],
            ),
          ),
        ),
        Expanded(
          child: records.isEmpty
              ? _EmptyState()
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    bottomBarInset(context) + 24,
                  ),
                  itemCount: records.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return Semantics(
                      button: true,
                      container: true,
                      excludeSemantics: true,
                      label:
                          '${record.timeText}，${record.node.hostname}，'
                          '下行 ${record.down.avg.toStringAsFixed(1)} Mbps，'
                          '上行 ${record.up.avg.toStringAsFixed(1)} Mbps，'
                          '评分 ${record.score} ${record.grade}',
                      child: _HistoryTile(
                        record: record,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => RecordDetailPage(record: record),
                          ),
                        ),
                        onDelete: () => state.deleteRecord(record.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, AppState state) async {
    if (state.history.isEmpty) return;
    try {
      final path = await state.exportHistory();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'text/csv')],
          text: 'Flutter 网测 · 历史记录',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    }
  }

  Future<void> _clear(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部记录？'),
        content: const Text('该操作不可撤销，导出的文件不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) await state.clearHistory();
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.insights_rounded,
                size: 36, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text('还没有测速记录', style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            '完成一次测速后结果会自动保存在这里',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  final TestRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final palette = context.palette;

    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: Pressable(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${record.score}',
                      style: text.headlineSmall?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: _scoreColor(record.score, scheme, palette),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.grade,
                      style: text.labelSmall?.copyWith(
                        color: _scoreColor(record.score, scheme, palette)
                            .withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.node.hostname.isEmpty
                          ? record.node.hostip
                          : record.node.hostname,
                      style: text.titleMedium?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.timeText,
                      style: text.bodySmall?.copyWith(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 只保留上下行两项：延迟/抖动/丢包在详情页看，列表不再挤爆宽度
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _InlineMetric(
                          icon: Icons.south_rounded,
                          value: record.down.avg,
                          color: palette.downloadGradient.first,
                        ),
                        _InlineMetric(
                          icon: Icons.north_rounded,
                          value: record.up.avg,
                          color: palette.uploadGradient.first,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

Color _scoreColor(int score, ColorScheme scheme, AppPalette palette) {
  if (score >= 90) return palette.success;
  if (score >= 75) return scheme.primary;
  if (score >= 55) return palette.warning;
  return scheme.error;
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          value.toStringAsFixed(value >= 1000 ? 0 : 1),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
        Text(
          ' Mbps',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class RecordDetailPage extends StatelessWidget {
  const RecordDetailPage({super.key, required this.record});

  final TestRecord record;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('测速详情'),
        actions: [
          IconButton(
            tooltip: '分享结果图',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => showResultSheet(context, record),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          SectionCard(
            child: Row(
              children: [
                ScoreRing(
                  score: record.score,
                  grade: record.grade,
                  size: 96,
                  colors: palette.downloadGradient,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.timeText, style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${record.node.hostname} · ${record.node.hostip}:${record.node.port}',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (record.node.oper.isNotEmpty)
                            StatusPill(label: record.node.oper, filled: true),
                          if (record.netTag.isNotEmpty)
                            NetTagPill(
                              tag: record.netTag,
                              kind: record.netKind,
                              filled: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('下行', style: text.titleSmall),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      record.down.avg.toStringAsFixed(1),
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.downloadGradient.first,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Mbps', style: text.labelSmall),
                    const Spacer(),
                    Text(
                      '峰值 ${record.down.max.toStringAsFixed(1)} Mbps',
                      style: text.bodySmall?.copyWith(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Sparkline(
                  samples: record.down.samples,
                  colors: palette.downloadGradient,
                  height: 100,
                  emptyHint: '无采样数据',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('上行', style: text.titleSmall),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      record.up.avg.toStringAsFixed(1),
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.uploadGradient.first,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('Mbps', style: text.labelSmall),
                    const Spacer(),
                    Text(
                      '峰值 ${record.up.max.toStringAsFixed(1)} Mbps',
                      style: text.bodySmall?.copyWith(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Sparkline(
                  samples: record.up.samples,
                  colors: palette.uploadGradient,
                  height: 100,
                  emptyHint: '未测试上行',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _DetailMetric(
                  label: '延迟',
                  value: '${record.ping.avg.toStringAsFixed(1)} ms',
                ),
                _DetailMetric(
                  label: '抖动',
                  value: '${record.ping.jitter.toStringAsFixed(1)} ms',
                ),
                _DetailMetric(
                  label: '丢包',
                  value: '${record.ping.loss.toStringAsFixed(0)} %',
                ),
                _DetailMetric(
                  label: 'DNS',
                  value: record.dnsMs > 0
                      ? '${record.dnsMs.toStringAsFixed(1)} ms'
                      : '--',
                ),
                _DetailMetric(
                  label: '本机 IP',
                  value: record.net.isEmpty ? '--' : record.net,
                ),
                _DetailMetric(
                  label: '会话',
                  value: record.uuid.isEmpty
                      ? '--'
                      : '${record.uuid.split('-').first}…',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
        ],
      ),
    );
  }
}
