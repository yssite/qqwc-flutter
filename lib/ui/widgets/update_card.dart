/// 设置页里的「检查更新」卡片，以及启动时的「发现新版本」提示条。
library;

import 'package:flutter/material.dart';

import '../../data/update_service.dart';
import 'common.dart';
import 'update_sheet.dart';

class UpdateCard extends StatelessWidget {
  const UpdateCard({
    super.key,
    required this.version,
    this.autoCheck = true,
    this.onAutoCheckChanged,
  });

  final String version;
  final bool autoCheck;
  final ValueChanged<bool>? onAutoCheckChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: UpdateService.instance,
      builder: (context, _) {
        final s = UpdateService.instance;
        final found =
            s.phase == UpdatePhase.found ||
            s.phase == UpdatePhase.ready ||
            s.phase == UpdatePhase.downloading;

        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('检查更新', style: text.titleMedium),
                        Text(
                          '当前版本 $version',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (found && s.info != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'v${s.info!.version}',
                        style: text.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              if (s.phase == UpdatePhase.downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: s.total > 0 ? s.progress : null,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_mb(s.received)} / ${_mb(s.total)} MB · 分段并发下载中',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ] else if (s.message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  s.message,
                  style: text.bodySmall?.copyWith(
                    color: s.phase == UpdatePhase.error
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: s.busy
                          ? null
                          : () => s.check(
                              currentVersion: version,
                              dueOnly: false,
                            ),
                      icon: Icon(_icon(s.phase), size: 18),
                      label: Text(_label(s.phase)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  if (found) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: s.busy
                            ? null
                            : () => showUpdateSheet(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('查看详情'),
                      ),
                    ),
                  ],
                ],
              ),
              if (onAutoCheckChanged != null)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('启动时自动检查更新'),
                  subtitle: const Text('6 小时内只请求一次 GitHub'),
                  value: autoCheck,
                  onChanged: onAutoCheckChanged,
                ),
              if (s.phase == UpdatePhase.latest)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '已是最新版本 · 检查失败时请确认网络能访问 GitHub',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static IconData _icon(UpdatePhase p) => switch (p) {
    UpdatePhase.checking => Icons.hourglass_top_rounded,
    UpdatePhase.downloading => Icons.downloading_rounded,
    UpdatePhase.found => Icons.download_rounded,
    UpdatePhase.ready => Icons.install_mobile_rounded,
    UpdatePhase.latest => Icons.check_circle_outline_rounded,
    _ => Icons.refresh_rounded,
  };

  static String _label(UpdatePhase p) => switch (p) {
    UpdatePhase.checking => '正在检查…',
    UpdatePhase.downloading => '正在下载…',
    _ => '检查更新',
  };

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}

/// 启动时检测到新版本时显示的提示条：`检测到新版本：1.3.0   详情 / 更新`
void showUpdateBanner(BuildContext context) {
  final s = UpdateService.instance;
  final info = s.info;
  if (info == null) return;
  final scheme = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 10),
      // 抬到底部导航栏之上，避免被胶囊挡住
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 92),
      content: Row(
        children: [
          Icon(Icons.new_releases_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '检测到新版本：${info.version}',
              style: text.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              showUpdateSheet(context);
            },
            child: const Text('详情'),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              s.download();
            },
            child: const Text('更新'),
          ),
        ],
      ),
    ),
  );
}
