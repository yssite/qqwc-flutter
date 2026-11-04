import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/node.dart';
import '../permission_sheet.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final settings = state.settings;
    final provinces = NodeRepository.provinces(state.nodes);
    final placeText = !state.permissions.location
        ? '未授权，按出口 IP 匹配'
        : (state.place == null
              ? (state.locationTried ? '定位失败，按出口 IP 匹配' : '获取中…')
              : [
                  state.place!.province,
                  state.place!.city,
                ].where((e) => e.isNotEmpty).join(' '));

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            bottomBarInset(context) + 24,
          ),
          sliver: SliverList.list(
            children: [
              const PageHeader(
                title: '设置',
                subtitle: '测速参数 · 节点偏好 · 网络与定位',
              ),

              // -------- 测速参数 --------
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Title(
                      icon: Icons.speed_rounded,
                      title: '测速参数',
                      subtitle: '同时影响上行与下行',
                    ),
                    const SizedBox(height: 16),
                    Text('单向上传时长', style: text.labelLarge),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 5, label: Text('5s')),
                        ButtonSegment(value: 8, label: Text('8s')),
                        ButtonSegment(value: 15, label: Text('15s')),
                        ButtonSegment(value: 30, label: Text('30s')),
                      ],
                      selected: {
                        [5, 8, 15, 30].contains(settings.durationSec)
                            ? settings.durationSec
                            : 8
                      },
                      onSelectionChanged: (v) => state.updateSettings(
                        (s) => s.durationSec = v.first,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SliderTile(
                      label: '下行连接数',
                      value: '${settings.downThreads}',
                      value2: settings.downThreads.toDouble(),
                      min: 1,
                      max: 16,
                      divisions: 15,
                      onChanged: (v) => state.updateSettings(
                        (s) => s.downThreads = v.round(),
                      ),
                    ),
                    _SliderTile(
                      label: '上行连接数',
                      value: '${settings.upThreads}',
                      value2: settings.upThreads.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      onChanged: (v) => state.updateSettings(
                        (s) => s.upThreads = v.round(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('跳过上行测速'),
                      subtitle: const Text('只测下行，耗时减半'),
                      value: settings.skipUpload,
                      onChanged: (v) => state.updateSettings(
                        (s) => s.skipUpload = v,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // -------- 节点偏好 --------
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Title(
                      icon: Icons.hub_rounded,
                      title: '节点偏好',
                      subtitle: '影响自动匹配的候选范围',
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动匹配最优节点'),
                      subtitle: const Text('按出口 IP / 省份 / 运营商选择'),
                      value: settings.autoMatch,
                      onChanged: (v) => state.updateSettings(
                        (s) => s.autoMatch = v,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('运营商', style: text.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('不限'),
                          selected: settings.oper.isEmpty,
                          onSelected: (_) => state.updateSettings(
                            (s) => s.oper = '',
                          ),
                        ),
                        for (final oper in NodeRepository.operList)
                          FilterChip(
                            label: Text(oper),
                            selected: settings.oper == oper,
                            onSelected: (_) => state.updateSettings(
                              (s) => s.oper = oper,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: provinces.contains(settings.province)
                          ? settings.province
                          : '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '偏好省份',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('就近自动')),
                        for (final p in provinces)
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) => state.updateSettings(
                        (s) => s.province = v ?? '',
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: state.nodesRefreshing
                            ? null
                            : () async {
                                await state.refreshNodes();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      state.nodesMessage ?? '节点表已更新',
                                    ),
                                  ),
                                );
                              },
                        icon: state.nodesRefreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_download_outlined, size: 18),
                        label: Text(state.nodesRefreshing
                            ? '正在更新…'
                            : '更新节点表（${state.nodes.length}）'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // -------- 网络与定位 --------
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Title(
                      icon: Icons.my_location_rounded,
                      title: '网络与定位',
                      subtitle: '权限状态与省份匹配来源',
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('用定位匹配省份'),
                      subtitle: const Text('定位优先，运营商仍按出口 IP 判断'),
                      value: settings.autoLocate,
                      onChanged: (v) async {
                        await state.updateSettings((s) => s.autoLocate = v);
                        if (!v) return;
                        if (!state.permissions.location) {
                          if (context.mounted) await requestWithSheet(context);
                        } else {
                          await state.refreshLocation();
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    _PermissionRow(
                      icon: Icons.my_location_rounded,
                      label: '定位',
                      granted: state.permissions.location,
                      detail: placeText,                    ),
                    _PermissionRow(
                      icon: Icons.signal_cellular_alt_rounded,
                      label: '电话状态',
                      granted: state.permissions.phone,
                      detail: state.link.detail.isEmpty
                          ? '仅读取网络制式与频段'
                          : state.link.detail,
                    ),
                    if (!state.permissions.any) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => requestWithSheet(context),
                          icon: const Icon(Icons.lock_open_rounded, size: 18),
                          label: const Text('申请权限'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // -------- 关于 --------
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Title(
                      icon: Icons.info_outline_rounded,
                      title: '关于',
                      subtitle: state.version.name.isEmpty
                          ? 'Flutter 网测 · 移动版'
                          : 'Flutter 网测 · 移动版 ${state.version.name}',
                    ),
                    const SizedBox(height: 14),
                    _KvRow(
                      label: '设备标识',
                      value: settings.deviceId,
                      mono: true,
                    ),
                    _KvRow(
                      label: '本机地址',
                      value: state.netInfo.localIp.isEmpty
                          ? '--'
                          : state.netInfo.localIp,
                    ),
                    _KvRow(
                      label: '出口 IP',
                      value: state.netInfo.ip.isEmpty ? '--' : state.netInfo.ip,
                    ),
                    _KvRow(
                      label: '节点库',
                      value: '${state.nodes.length} 个 · 内置 + 远端增量',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '协议来自 CAICT「全球网测」Android 4.4.8 的公开接口，'
                      '结果仅保存在本机，不上传任何测速数据。'
                      '本项目用于互操作性与学习研究。',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              // 页面最底部的版本水印：数值直接来自安装包
              Center(
                child: Column(
                  children: [
                    Text(
                      'Flutter 网测',
                      style: text.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      state.version.display,
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleMedium),
            if (subtitle != null)
              Text(
                subtitle!,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 权限状态一行：图标 + 名称 + 说明 + 状态胶囊
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.granted,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final bool granted;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodyMedium),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(
            label: granted ? '已授权' : '未授权',
            filled: granted,
            color: granted ? scheme.primary : null,
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.value2,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String value;
  final double value2;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: text.labelLarge),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                value,
                style: text.labelMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value2.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                fontFeatures: mono
                    ? const [FontFeature.tabularFigures()]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
