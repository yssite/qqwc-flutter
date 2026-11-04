import 'package:flutter/material.dart';

import '../../app.dart';
import '../../app_state.dart';
import '../../data/link_service.dart';
import '../../data/store.dart';
import '../../engine/models.dart';
import '../../theme/app_theme.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/common.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  late final TextEditingController _pingHost;
  late final TextEditingController _pingPort;
  late final TextEditingController _dnsHost;

  PingStat? _ping;
  bool _pinging = false;
  DiagResult? _dns;
  bool _dnsResolving = false;
  List<DiagResult>? _reachability;
  bool _checkingReach = false;

  @override
  void initState() {
    super.initState();
    final node = AppScope.of(context, listen: false).live.node;
    _pingHost = TextEditingController(text: node?.hostip ?? '223.5.5.5');
    _pingPort = TextEditingController(text: '${node?.portNum ?? 443}');
    _dnsHost = TextEditingController(text: 'www.baidu.com');
  }

  @override
  void dispose() {
    _pingHost.dispose();
    _pingPort.dispose();
    _dnsHost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        bottomBarInset(context) + 24,
      ),
      children: [
        const PageHeader(
          title: '网络诊断',
          subtitle: '连接情况 · 出口信息 · 延迟 · DNS',
        ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('网络环境', style: text.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        await state.refreshLink();
                        await state.refreshNetInfo();
                        await state.refreshLocation();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('刷新'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _InfoRow(
                  label: '连接类型',
                  value: _linkTypeLabel(state.link),
                ),
                if (state.link.detail.isNotEmpty)
                  _InfoRow(label: '连接情况', value: state.link.detail),
                _InfoRow(label: '本机地址', value: state.netInfo.localIp.isEmpty ? '--' : state.netInfo.localIp),
                _InfoRow(label: '出口 IP', value: state.netInfo.ip.isEmpty ? '--' : state.netInfo.ip),
                _InfoRow(
                  label: '归属地',
                  value: state.netInfo.locationText.isEmpty
                      ? '--'
                      : state.netInfo.locationText,
                ),
                _InfoRow(
                  label: '运营商',
                  value: _operLabel(state),
                ),
                _InfoRow(
                  label: '定位省份',
                  value: _placeLabel(state),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Ping
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('TCP 延迟', style: text.titleMedium),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '对目标端口做 5 次 TCP 握手，得到时延/抖动/丢包',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _pingHost,
                        decoration: const InputDecoration(
                          labelText: '主机',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _pingPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '端口',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _pinging ? null : _runPing,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(_pinging ? '测量中…' : '开始测量'),
                      ),
                    ),
                  ],
                ),
                if (_ping != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: '平均',
                          value: _ping!.avg.toStringAsFixed(1),
                          unit: 'ms',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          label: '抖动',
                          value: _ping!.jitter.toStringAsFixed(1),
                          unit: 'ms',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          label: '丢包',
                          value: _ping!.loss.toStringAsFixed(0),
                          unit: '%',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // DNS
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.travel_explore_rounded,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('DNS 解析', style: text.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dnsHost,
                  decoration: const InputDecoration(
                    labelText: '域名',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _dnsResolving ? null : _runDns,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(_dnsResolving ? '解析中…' : '解析'),
                ),
                if (_dns != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        _dns!.ok
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        size: 18,
                        color: _dns!.ok
                            ? context.palette.success
                            : scheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_dns!.value}  ·  ${_dns!.subtitle}',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                  if (_dns!.details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _dns!.details.join('   '),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Reachability
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.public_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('连通质量', style: text.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: _checkingReach ? null : _runReach,
                      child: Text(_checkingReach ? '检测中' : '开始检测'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '对国内主要骨干节点与公共 DNS 做一次握手探测',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (_reachability != null) ...[
                  const SizedBox(height: 10),
                  for (final item in _reachability!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            item.ok
                                ? Icons.circle
                                : Icons.radio_button_unchecked,
                            size: 9,
                            color: item.ok
                                ? context.palette.success
                                : scheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title, style: text.bodyMedium),
                                Text(
                                  item.subtitle,
                                  style: text.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            item.value,
                            style: text.titleSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: item.ok
                                  ? null
                                  : scheme.error.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _runPing() async {
    final state = AppScope.of(context, listen: false);
    final host = _pingHost.text.trim();
    final port = int.tryParse(_pingPort.text.trim()) ?? 443;
    if (host.isEmpty) return;
    setState(() {
      _pinging = true;
      _ping = null;
    });
    final stat = await state.diagPing(host, port);
    if (!mounted) return;
    setState(() {
      _pinging = false;
      _ping = stat;
    });
  }

  Future<void> _runDns() async {
    final state = AppScope.of(context, listen: false);
    final host = _dnsHost.text.trim();
    if (host.isEmpty) return;
    setState(() {
      _dnsResolving = true;
      _dns = null;
    });
    final result = await state.diagDns(host);
    if (!mounted) return;
    setState(() {
      _dnsResolving = false;
      _dns = result;
    });
  }

  Future<void> _runReach() async {
    final state = AppScope.of(context, listen: false);
    setState(() {
      _checkingReach = true;
      _reachability = null;
    });
    final results = await state.diagReachability();
    if (!mounted) return;
    setState(() {
      _checkingReach = false;
      _reachability = results;
    });
  }
}

/// 连接类型：Wi-Fi / 蜂窝网络（含 VPN 叠加说明）
String _linkTypeLabel(LinkInfo link) {
  final base = switch (link.kind) {
    LinkKind.wifi => 'Wi-Fi',
    LinkKind.cellular => '蜂窝网络',
    LinkKind.ethernet => '以太网',
    LinkKind.vpn => 'VPN',
    LinkKind.other => '其他连接',
    LinkKind.none => '未连接',
  };
  if (link.vpn && link.kind != LinkKind.vpn) return '$base（VPN）';
  return base;
}

/// 运营商行：数据卡运营商（带卡槽）+ 出口 IP 运营商（不一致时才额外标注）
String _operLabel(AppState state) {
  final oper = state.effectiveOper;
  final ipOper = state.netInfo.oper;
  final parts = <String>[];
  if (oper.isNotEmpty) parts.add(state.operWithSlot);
  if (state.link.isCellular &&
      ipOper.isNotEmpty &&
      ipOper != oper) {
    parts.add('出口 IP $ipOper');
  }
  if (parts.isEmpty) {
    return state.netInfo.isp.isEmpty ? '--' : state.netInfo.isp;
  }
  return parts.join(' · ');
}

/// 定位省份行：区分「已定位」「定位中」「定位失败」「未授权」
String _placeLabel(AppState state) {
  if (!state.permissions.location) return '未授权（按出口 IP）';
  final place = state.place;
  if (place == null) {
    return state.locationTried ? '定位失败（按出口 IP）' : '获取中…';
  }
  final text = [place.province, place.city].where((e) => e.isNotEmpty).join(' ');
  if (text.isEmpty) return '定位失败（按出口 IP）';
  return '$text · 定位';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
