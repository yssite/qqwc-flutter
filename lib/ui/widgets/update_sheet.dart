/// 更新详情弹层：版本、更新说明、下载进度与安装入口。
library;

import 'package:flutter/material.dart';

import '../../data/update_service.dart';
import 'markdown_text.dart';

Future<void> showUpdateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const UpdateSheet(),
  );
}

class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);

    return AnimatedBuilder(
      animation: UpdateService.instance,
      builder: (context, _) {
        final s = UpdateService.instance;
        final info = s.info;
        return Padding(
          padding: EdgeInsets.fromLTRB(22, 4, 22, 18 + media.padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('发现新版本', style: text.headlineSmall),
                  const SizedBox(width: 8),
                  if (info != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'v${info.version}',
                        style: text.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                info == null ? '已是最新版本' : '当前版本 ${_currentVersion(context)}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (info != null && info.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: media.size.height * 0.36,
                  ),
                  child: SingleChildScrollView(
                    child: MarkdownText(
                      info.notes.trim(),
                      baseStyle: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.55,
                      ),
                    ),
                  ),
                ),
              ],
              if (s.phase == UpdatePhase.downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: s.total > 0 ? s.progress : null,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_mb(s.received)} / ${_mb(s.total)} MB · 分段并发下载',
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (s.phase == UpdatePhase.downloading) {
                          s.cancelDownload();
                        } else {
                          s.openReleasePage();
                        }
                      },
                      icon: Icon(
                        s.phase == UpdatePhase.downloading
                            ? Icons.close_rounded
                            : Icons.open_in_new_rounded,
                        size: 18,
                      ),
                      label: Text(
                        s.phase == UpdatePhase.downloading ? '取消下载' : '在浏览器打开',
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: s.busy ? null : s.primaryAction,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        s.phase == UpdatePhase.downloading
                            ? '下载中…'
                            : s.phase == UpdatePhase.ready
                                ? '安装'
                                : '下载并安装',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _currentVersion(BuildContext context) {
    // 详情弹层不依赖 AppState，版本号从 UpdateService 的文案里拿不到时用占位
    return UpdateService.instance.currentVersion.isEmpty
        ? '--'
        : UpdateService.instance.currentVersion;
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
