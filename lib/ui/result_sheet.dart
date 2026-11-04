import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../engine/models.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';
import 'widgets/net_tag.dart';
import 'widgets/score_ring.dart';
import 'widgets/sparkline.dart';

Future<void> showResultSheet(BuildContext context, TestRecord record) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ResultSheet(record: record),
  );
}

class ResultSheet extends StatefulWidget {
  const ResultSheet({super.key, required this.record});

  final TestRecord record;

  @override
  State<ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<ResultSheet> {
  final GlobalKey _captureKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final media = MediaQuery.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + media.padding.bottom),
          children: [
            Center(
              child: RepaintBoundary(
                key: _captureKey,
                child: Container(
                  width: 380,
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.alphaBlend(
                          palette.downloadGradient.first.withValues(alpha: 0.14),
                          scheme.surfaceContainerLow,
                        ),
                        scheme.surfaceContainerLow,
                      ],
                    ),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Flutter 网测',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            record.timeText,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          ScoreRing(
                            score: record.score,
                            grade: record.grade,
                            size: 108,
                            colors: palette.downloadGradient,
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.node.hostname.isEmpty
                                      ? record.node.hostip
                                      : record.node.hostname,
                                  style: text.titleLarge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${record.node.hostip}:${record.node.port}',
                                  style: text.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    // 优先显示测速时实际在跑的运营商，而不是节点归属
                                    if (record.oper.isNotEmpty ||
                                        record.node.oper.isNotEmpty)
                                      StatusPill(
                                        label: record.oper.isNotEmpty
                                            ? record.oper
                                            : record.node.oper,
                                        filled: true,
                                      ),
                                    if (record.netTag.isNotEmpty)
                                      NetTagPill(
                                        tag: record.netTag,
                                        kind: record.netKind,
                                        filled: true,
                                      ),
                                    StatusPill(
                                      label: '延迟 ${_num(record.ping.avg)} ms',
                                      filled: true,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _BigMetric(
                              label: '下行',
                              value: record.down.avg,
                              color: palette.downloadGradient.first,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 44,
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                          Expanded(
                            child: _BigMetric(
                              label: '上行',
                              value: record.up.avg,
                              color: palette.uploadGradient.first,
                              alignEnd: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _SparkRow(record: record),
                      const SizedBox(height: 16),
                      Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 18,
                        runSpacing: 10,
                        children: [
                          _MiniStat(
                            label: '峰值下行',
                            value: '${_num(record.down.max)} Mbps',
                          ),
                          _MiniStat(
                            label: '峰值上行',
                            value: '${_num(record.up.max)} Mbps',
                          ),
                          _MiniStat(
                            label: '抖动',
                            value: '${record.ping.jitter.toStringAsFixed(1)} ms',
                          ),
                          _MiniStat(
                            label: '丢包',
                            value: '${record.ping.loss.toStringAsFixed(0)} %',
                          ),
                          if (record.dnsMs > 0)
                            _MiniStat(
                              label: 'DNS',
                              value: '${record.dnsMs.toStringAsFixed(1)} ms',
                            ),
                          if (record.net.isNotEmpty)
                            _MiniStat(label: '本机 IP', value: record.net),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(_sharing ? '正在生成…' : '分享结果图'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      state.startTest(node: record.node);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('再测一次'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  shape: const StadiumBorder(),
                ),
                child: const Text('完成'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('结果卡片尚未渲染');
      final image = await boundary.toImage(pixelRatio: 2.4);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('图片编码失败');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/globalspeed_${widget.record.id}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: 'Flutter 网测 · 下行 ${_num(widget.record.down.avg)} Mbps / '
              '上行 ${_num(widget.record.up.avg)} Mbps / '
              '延迟 ${_num(widget.record.ping.avg)} ms',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  static String _num(double v) =>
      v >= 1000 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _BigMetric extends StatelessWidget {
  const _BigMetric({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final double value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.labelMedium?.copyWith(
            color: color,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment:
              alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value.toStringAsFixed(value >= 1000 ? 0 : 1),
                  style: text.displaySmall?.copyWith(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('Mbps', style: text.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
          ],
        ),
      ],
    );
  }
}

class _SparkRow extends StatelessWidget {
  const _SparkRow({required this.record});

  final TestRecord record;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('下行曲线',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.downloadGradient.first,
                      )),
              const SizedBox(height: 4),
              Sparkline(
                samples: record.down.samples,
                colors: palette.downloadGradient,
                height: 46,
                emptyHint: '',
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('上行曲线',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.uploadGradient.first,
                      )),
              const SizedBox(height: 4),
              Sparkline(
                samples: record.up.samples,
                colors: palette.uploadGradient,
                height: 46,
                emptyHint: '',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
