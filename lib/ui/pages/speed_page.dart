import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../app_state.dart';
import '../../data/link_service.dart';
import '../../engine/models.dart';
import '../../theme/app_theme.dart';
import '../result_sheet.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/brand_mark.dart';
import '../widgets/needle_gauge.dart';
import '../widgets/sparkline.dart';

/// 首页结构参考 Speedtest 移动端：顶部读数 → 小指标 → 曲线 → 指针仪表盘 →
/// 服务器信息 → 主按钮；配色与动效遵循 Material 3 Expressive。
class SpeedPage extends StatefulWidget {
  const SpeedPage({
    super.key,
    required this.onOpenNodes,
    required this.onOpenNetwork,
  });

  final VoidCallback onOpenNodes;

  /// 点击右上角网络标识 → 跳转网络诊断
  final VoidCallback onOpenNetwork;

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> {
  String? _shownRecordId;
  double _gaugeMax = 100;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final live = state.live;
    final palette = context.palette;

    _maybeShowResult(state);

    final running = live.isRunning;
    final result = live.result;
    final uploadView = running && live.liveUpload;

    final peak = <double>[
      live.liveSpeed,
      live.downResult?.max ?? 0,
      live.upResult?.max ?? 0,
      result?.down.avg ?? 0,
      result?.up.avg ?? 0,
    ].reduce(math.max);
    if (peak > _gaugeMax) _gaugeMax = _niceMax(peak);

    final gaugeValue = running
        ? live.liveSpeed
        : (live.downResult?.avg ?? result?.down.avg ?? 0);

    final down =
        live.downResult?.avg ??
        result?.down.avg ??
        (live.phase == TestPhase.download ? live.liveSpeed : null);
    final up =
        live.upResult?.avg ??
        result?.up.avg ??
        (live.phase == TestPhase.upload ? live.liveSpeed : null);
    final ping = live.ping.avg > 0
        ? live.ping
        : (result?.ping ?? const PingStat());

    final gaugeLabel = switch (live.phase) {
      TestPhase.matching => '匹配节点',
      TestPhase.ping => '测量延迟',
      TestPhase.download => '下行速率',
      TestPhase.upload => '上行速率',
      TestPhase.finishing => '生成报告',
      TestPhase.done => '下行平均',
      TestPhase.failed => '测速失败',
      TestPhase.canceled => '已取消',
      TestPhase.idle => '',
    };

    final hasChart =
        state.live.downSamples.isNotEmpty ||
        state.live.upSamples.isNotEmpty ||
        state.live.result != null;
    final failed = live.phase == TestPhase.failed && live.error != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final short = constraints.maxHeight < 660;
        // 宽度与可用高度共同决定仪表盘尺寸：小屏/高 DPI 自动收一档，
        // 再配合外层滚动，保证「开始测速」永远可达。
        final gaugeSide = math.min(
          width - 48,
          math.min(constraints.maxHeight * (short ? 0.40 : 0.46), 400.0),
        );

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(
              link: state.link,
              carrier: state.effectiveOper,
              onOpenNetwork: widget.onOpenNetwork,
            ),
            const SizedBox(height: 6),
            _DownUpRow(
              down: down,
              up: up,
              active: uploadView,
              palette: palette,
              running: running,
            ),
            const SizedBox(height: 8),
            _MiniStats(ping: ping),
            const SizedBox(height: 4),
            if (hasChart)
              _LiveChart(
                state: state,
                palette: palette,
                height: short ? 36 : 50,
              ),
          ],
        );

        final gauge = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: IgnorePointer(
                child: SizedBox(
                  width: gaugeSide,
                  child: NeedleGauge(
                    value: gaugeValue,
                    maxValue: _gaugeMax,
                    phase: live.phase,
                    label: gaugeLabel,
                    upload: uploadView,
                    score: result?.score,
                    grade: result?.grade,
                  ),
                ),
              ),
            ),
            if (!failed) _StatusLine(live: live, running: running),
          ],
        );

        final footer = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ServerRow(
              state: state,
              onOpenNodes: widget.onOpenNodes,
              compact: short,
            ),
            if (failed) ...[
              const SizedBox(height: 8),
              _ErrorBanner(
                message: live.error!,
                onRetry: () {
                  _shownRecordId = null;
                  _gaugeMax = 100;
                  // 失败多半是网络变了，重试也要重新匹配节点
                  state.startTest();
                },
              ),
            ],
            const SizedBox(height: 10),
            _PrimaryAction(
              running: running,
              done: live.phase == TestPhase.done,
              onPressed: () {
                HapticFeedback.lightImpact();
                if (running) {
                  state.stopTest();
                } else {
                  _shownRecordId = null;
                  _gaugeMax = 100;
                  // 每次点「开始测速」都重新按当前网络匹配节点：
                  // 上一轮节点的运营商/省份可能已经随换卡、切 WiFi 变了。
                  state.startTest();
                }
              },
            ),
          ],
        );

        // 用 spaceBetween 代替 Spacer：内容放得下时把富余空间分给三段留白，
        // 放不下时（小屏 / 高 DPI）各段贴紧排列并允许滚动，不会再把按钮挤没。
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 4, 20, bottomBarInset(context) + 20),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                minHeight: math.max(
                  0,
                  constraints.maxHeight - bottomBarInset(context) - 24,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: gauge,
                  ),
                  footer,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _maybeShowResult(AppState state) {
    final record = state.live.result;
    if (record == null || state.live.phase != TestPhase.done) return;
    if (_shownRecordId == record.id) return;
    _shownRecordId = record.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showResultSheet(context, record);
    });
  }

  static double _niceMax(double peak) {
    if (peak <= 20) return 50;
    if (peak <= 50) return 100;
    if (peak <= 120) return 200;
    if (peak <= 300) return 500;
    if (peak <= 600) return 1000;
    if (peak <= 1200) return 2000;
    return 5000;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.link,
    required this.carrier,
    required this.onOpenNetwork,
  });

  final LinkInfo link;
  final String carrier;
  final VoidCallback onOpenNetwork;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        const BrandMark(size: 30),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Flutter 网测',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _LinkChip(link: link, carrier: carrier, onTap: onOpenNetwork),
      ],
    );
  }
}

/// 右上角链路标识：`电信 · 5G n41` / `电信 · 5G WiFi6` / `移动 · 4G`
class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.link,
    required this.carrier,
    required this.onTap,
  });

  final LinkInfo link;
  final String carrier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final tag = link.tag;
    final label = [carrier, tag].where((e) => e.isNotEmpty).join(' · ');
    final shown = label.isEmpty ? '识别网络…' : label;

    final icon = switch (link.kind) {
      LinkKind.wifi => Icons.wifi_rounded,
      LinkKind.cellular => Icons.signal_cellular_alt_rounded,
      LinkKind.ethernet => Icons.settings_ethernet_rounded,
      LinkKind.vpn => Icons.vpn_key_rounded,
      _ => Icons.language_rounded,
    };

    return Semantics(
      button: true,
      label: '当前网络 $shown，点击查看网络诊断',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownUpRow extends StatelessWidget {
  const _DownUpRow({
    required this.down,
    required this.up,
    required this.active,
    required this.palette,
    required this.running,
  });

  final double? down;
  final double? up;
  final bool active;
  final AppPalette palette;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _BigStat(
            label: '下行',
            value: down,
            color: palette.downloadGradient.first,
            alignEnd: false,
            highlight: running && !active,
          ),
        ),
        Container(
          width: 1,
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
        Expanded(
          child: _BigStat(
            label: '上行',
            value: up,
            color: palette.uploadGradient.first,
            alignEnd: true,
            highlight: running && active,
          ),
        ),
      ],
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.label,
    required this.value,
    required this.color,
    required this.alignEnd,
    required this.highlight,
  });

  final String label;
  final double? value;
  final Color color;
  final bool alignEnd;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final shown = value == null || value! <= 0
        ? '--'
        : (value! >= 1000
              ? value!.toStringAsFixed(0)
              : value!.toStringAsFixed(1));

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Icon(
              alignEnd ? Icons.north_rounded : Icons.south_rounded,
              size: 15,
              color: color.withValues(alpha: highlight ? 1 : 0.85),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: text.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  shown,
                  style: text.displaySmall?.copyWith(
                    fontFamily: AppFonts.mono,
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -2,
                    height: 1,
                    color: color,
                    fontFeatures: AppFonts.tabular,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Mbps',
              style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniStats extends StatelessWidget {
  const _MiniStats({required this.ping});

  final PingStat ping;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget item(String label, String value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: text.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
        Text(
          value,
          style: text.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        item(
          '延迟',
          ping.avg > 0 ? '${ping.avg.toStringAsFixed(0)} ms' : '-- ms',
        ),
        const SizedBox(width: 18),
        item(
          '抖动',
          ping.jitter > 0 ? '${ping.jitter.toStringAsFixed(1)} ms' : '-- ms',
        ),
        const SizedBox(width: 18),
        item('丢包', ping.avg > 0 ? '${ping.loss.toStringAsFixed(0)} %' : '-- %'),
      ],
    );
  }
}

class _LiveChart extends StatelessWidget {
  const _LiveChart({
    required this.state,
    required this.palette,
    required this.height,
  });

  final AppState state;
  final AppPalette palette;
  final double height;

  @override
  Widget build(BuildContext context) {
    final live = state.live;
    final result = live.result;
    final upload = live.isRunning && live.liveUpload;

    final liveSamples = (upload ? live.upSamples : live.downSamples)
        .map((e) => e.speed)
        .toList(growable: false);
    final finalSamples = upload
        ? (live.upResult?.samples ?? result?.up.samples ?? const <double>[])
        : (live.downResult?.samples ??
              result?.down.samples ??
              const <double>[]);
    final samples = liveSamples.isNotEmpty ? liveSamples : finalSamples;

    return SizedBox(
      height: height,
      child: Sparkline(
        samples: samples,
        colors: upload ? palette.uploadGradient : palette.downloadGradient,
        height: height,
        emptyHint: '',
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.live, required this.running});

  final LiveTest live;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final phase = live.phase;

    String value;
    if (running) {
      final seconds = (live.elapsedMs / 1000).toStringAsFixed(1);
      value = switch (phase) {
        TestPhase.matching => '正在匹配最优节点…',
        TestPhase.ping => '正在测量延迟…',
        TestPhase.download => '正在测速 · 下行 $seconds s',
        TestPhase.upload => '正在测速 · 上行 $seconds s',
        TestPhase.finishing => '正在生成报告…',
        _ => '正在测速…',
      };
    } else if (phase == TestPhase.done && live.result != null) {
      final r = live.result!;
      value = '测速完成 · ${r.score} ${r.grade} · ${r.timeText.substring(11)}';
    } else if (phase == TestPhase.failed) {
      final err = live.error;
      value = err == null || err.isEmpty ? '测速失败，点下方按钮重试' : err;
    } else if (phase == TestPhase.canceled) {
      value = '已取消，结果未保存';
    } else {
      final node = live.node;
      value = node == null ? '点击下方开始测速' : '${node.hostname} · 准备就绪';
    }

    return SizedBox(
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (running)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: scheme.primary,
              ),
            )
          else if (phase == TestPhase.done)
            Icon(
              Icons.check_circle_rounded,
              size: 13,
              color: context.palette.success,
            ),
          if (running || phase == TestPhase.done) const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.state,
    required this.onOpenNodes,
    this.compact = false,
  });

  final AppState state;
  final VoidCallback onOpenNodes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final node = state.live.node ?? state.live.result?.node;
    final net = state.netInfo;

    // 服务器卡：第一行地区/节点名，第二行 IP:端口（不再重复运营商）
    final serverTitle = node == null
        ? '自动选择'
        : (node.hostname.isEmpty ? node.hostip : node.hostname);
    final serverSubtitle = node == null
        ? '就近匹配最优节点'
        : '${node.hostip}:${node.port}';

    // 网络卡：第一行归属地，第二行出口 IP
    final region = [
      net.province,
      net.city,
    ].where((e) => e.isNotEmpty).join(' ');
    final netTitle = region.isEmpty
        ? (net.oper.isNotEmpty
              ? net.oper
              : (net.isp.isEmpty ? '本机网络' : net.isp))
        : region;
    final netSubtitle = net.ip.isEmpty ? '--' : net.ip;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _InfoCard(
              icon: Icons.dns_rounded,
              label: '测速服务器',
              title: serverTitle,
              subtitle: serverSubtitle,
              onTap: state.live.isRunning ? null : onOpenNodes,
              trailing: state.live.isRunning
                  ? null
                  : Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _InfoCard(
              icon: Icons.language_rounded,
              label: '本机网络',
              title: netTitle,
              subtitle: netSubtitle,
              dense: compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: onTap != null,
      label: '$label，$title，$subtitle',
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              14,
              dense ? 10 : 12,
              10,
              dense ? 10 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    ?trailing,
                  ],
                ),
                SizedBox(height: dense ? 6 : 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.running,
    required this.done,
    required this.onPressed,
  });

  final bool running;
  final bool done;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (running) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.stop_rounded, size: 20, color: scheme.error),
              const SizedBox(width: 8),
              Text('停止测速', style: text.titleSmall),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, size: 22, color: scheme.onPrimary),
            const SizedBox(width: 8),
            Text(
              done ? '再测一次' : '开始测速',
              style: text.titleSmall?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
