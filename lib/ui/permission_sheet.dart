/// 权限说明面板：先讲清楚为什么要，再发起系统申请。
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/link_service.dart';
import 'widgets/common.dart';

/// 返回 true 表示用户同意申请（随后由调用方发起系统弹窗）。
Future<bool> showPermissionSheet(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => const _PermissionSheet(),
  );
  return ok ?? false;
}

class _PermissionSheet extends StatelessWidget {
  const _PermissionSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(22, 4, 22, 18 + media.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('让结果更准一点', style: text.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '需要两项系统权限，都只在本机使用，不会上传任何位置或设备信息。',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          const _PermissionItem(
            icon: Icons.my_location_rounded,
            title: '定位（精确位置）',
            body: '用你实际所在的省份匹配就近测速节点。出口 IP 的归属地偶尔会落到隔壁地市，'
                '定位可以纠正这一点；运营商仍然按出口 IP 判断。',
          ),
          const SizedBox(height: 14),
          const _PermissionItem(
            icon: Icons.signal_cellular_alt_rounded,
            title: '电话状态（只读网络信息）',
            body: '读取当前网络制式（5G / 4G）、频段与运营商，用于首页和结果卡上的网络标识。'
                '不会读取通话记录、短信或通讯录。',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('暂不允许'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('允许'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '之后可在「设置 → 网络与定位」随时调整',
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 首次启动/设置页共用的申请流程。
Future<LinkPermissions> requestWithSheet(BuildContext context) async {
  final state = AppScope.of(context, listen: false);
  final agreed = await showPermissionSheet(context);
  if (!agreed) return state.permissions;
  final perms = await state.requestPermissions();
  if (context.mounted && !perms.any) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('未获得授权，将按出口 IP 匹配省份')),
    );
  }
  return perms;
}

/// 权限状态胶囊（设置页用）
class PermissionPill extends StatelessWidget {
  const PermissionPill({super.key, required this.granted, this.label});

  final bool granted;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: label ?? (granted ? '已授权' : '未授权'),
      filled: granted,
    );
  }
}
