import 'package:flutter/material.dart';

import '../../app.dart';
import '../../app_state.dart';
import '../../core/node.dart';
import '../../theme/app_theme.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/common.dart';

class NodesPage extends StatefulWidget {
  const NodesPage({super.key, required this.onStartTest});

  final VoidCallback onStartTest;

  @override
  State<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends State<NodesPage> {
  final TextEditingController _search = TextEditingController();
  String _oper = '';
  String _province = '';
  bool _sortByLatency = false;
  bool _probing = false;
  int _probeDone = 0;
  int _probeTotal = 0;
  final Map<String, double> _latency = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final nodes = _filter(state.nodes);
    final shown = [...nodes];
    if (_sortByLatency) {
      shown.sort((a, b) {
        final la = _latency[a.key] ?? double.infinity;
        final lb = _latency[b.key] ?? double.infinity;
        return la.compareTo(lb);
      });
    }

    final provinces = NodeRepository.provinces(state.nodes);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: PageHeader(
            title: '测速节点',
            subtitle: '${state.nodes.length} 个全国节点 · 点击即可测速',
            trailing: IconButton.filledTonal(
              tooltip: '更新节点表',
              onPressed: state.nodesRefreshing ? null : () => _refresh(state),
              icon: state.nodesRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: SearchBar(
            controller: _search,
            hintText: '搜索节点 / IP / 城市',
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
            leading: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
            trailing: [
              if (_search.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
                ),
            ],
            onChanged: (_) => setState(() {}),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _OperChip(
                label: '全部运营商',
                selected: _oper.isEmpty,
                onSelected: () => setState(() => _oper = ''),
              ),
              for (final oper in NodeRepository.operList)
                _OperChip(
                  label: oper,
                  selected: _oper == oper,
                  onSelected: () => setState(() => _oper = oper),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
          child: Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _province,
                      isDense: true,
                      borderRadius: BorderRadius.circular(20),
                      icon: const Icon(Icons.expand_more_rounded, size: 18),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('全部省份')),
                        for (final p in provinces)
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) => setState(() => _province = v ?? ''),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: '按延迟排序',
                onPressed: () => setState(() => _sortByLatency = !_sortByLatency),
                icon: Icon(
                  _sortByLatency
                      ? Icons.sort_rounded
                      : Icons.sort_by_alpha_rounded,
                  size: 20,
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.tonalIcon(
                onPressed: _probing ? null : () => _probeBatch(state, shown),
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: Text(_probing ? '$_probeDone/$_probeTotal' : '测延迟'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
        ),
        if (_probing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _probeTotal == 0 ? null : _probeDone / _probeTotal,
                minHeight: 3,
              ),
            ),
          ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配的节点',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    bottomBarInset(context) + 24,
                  ),
                  itemCount: shown.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final node = shown[index];
                    final latency = _latency[node.key];
                    return Semantics(
                      button: true,
                      container: true,
                      excludeSemantics: true,
                      label: '${node.hostname}，${node.hostip}，'
                          '${node.operLabel}，'
                          '${latency == null ? '未测延迟' : (latency < 0 ? '不可达' : '延迟 ${latency.toStringAsFixed(0)} 毫秒')}',
                      child: _NodeTile(
                        node: node,
                        latency: latency,
                        onTap: () => _openNodeSheet(state, node),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<Node> _filter(List<Node> all) {
    final query = _search.text.trim().toLowerCase();
    return all.where((n) {
      if (_oper.isNotEmpty && n.oper != _oper) return false;
      if (_province.isNotEmpty && n.pname != _province) return false;
      if (query.isNotEmpty) {
        final hay =
            '${n.hostname} ${n.hostip} ${n.location} ${n.pname} ${n.oper}'
                .toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  Future<void> _probeBatch(AppState state, List<Node> list) async {
    final targets = list.take(60).toList(growable: false);
    if (targets.isEmpty) return;
    setState(() {
      _probing = true;
      _probeDone = 0;
      _probeTotal = targets.length;
    });
    final result = await state.probeNodes(
      targets,
      concurrency: 8,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _probeDone = done;
          _probeTotal = total;
        });
      },
    );
    if (!mounted) return;
    final failed = result.values.where((v) => v < 0).length;
    setState(() {
      _probing = false;
      _sortByLatency = true;
      result.forEach((index, ms) {
        if (index < targets.length) {
          _latency[targets[index].key] = ms;
        }
      });
    });
    if (failed == result.length && result.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('这些节点当前网络都连不上，试试就近省份或「电信」筛选'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _refresh(AppState state) async {
    await state.refreshNodes();
    if (!mounted) return;
    final message = state.nodesMessage ?? '已更新';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openNodeSheet(AppState state, Node node) async {
    final latency = _latency[node.key];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final text = Theme.of(sheetContext).textTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.hostname.isEmpty ? node.hostip : node.hostname,
                style: text.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${node.hostip}:${node.port}'
                '${node.oper.isNotEmpty ? ' · ${node.oper}' : ''}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: '省份',
                      value: node.pname.isEmpty ? '--' : node.pname,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: '延迟',
                      value: latency == null
                          ? '--'
                          : (latency < 0 ? '超时' : latency.toStringAsFixed(0)),
                      unit: latency == null || latency < 0 ? '' : 'ms',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        setState(() {
                          _latency[node.key] = -2;
                        });
                        final ms = await state.diagPing(node.hostip, node.portNum, count: 3);
                        if (!mounted) return;
                        setState(() => _latency[node.key] = ms.avg);
                        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                      },
                      icon: const Icon(Icons.timer_outlined, size: 18),
                      label: const Text('测延迟'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        state.startTest(node: node);
                        widget.onStartTest();
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('用此节点'),
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
}

class _OperChip extends StatelessWidget {
  const _OperChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onSelected(),
        labelStyle: Theme.of(context).textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.latency,
    required this.onTap,
  });

  final Node node;
  final double? latency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final palette = context.palette;

    final Color dot = switch (node.oper) {
      '电信' => const Color(0xFF2E7DF7),
      '联通' => const Color(0xFFE0534A),
      '移动' => const Color(0xFF12A15B),
      '教育网' => const Color(0xFF8E6BE8),
      '广电网' => const Color(0xFFE0A400),
      _ => scheme.outline,
    };

    String latencyText;
    Color latencyColor;
    if (latency == null) {
      latencyText = '--';
      latencyColor = scheme.onSurfaceVariant;
    } else if (latency! < 0) {
      latencyText = '超时';
      latencyColor = scheme.error;
    } else if (latency! < 30) {
      latencyText = '${latency!.toStringAsFixed(0)} ms';
      latencyColor = palette.success;
    } else if (latency! < 80) {
      latencyText = '${latency!.toStringAsFixed(0)} ms';
      latencyColor = palette.warning;
    } else {
      latencyText = '${latency!.toStringAsFixed(0)} ms';
      latencyColor = scheme.error;
    }

    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.hostname.isEmpty ? node.hostip : node.hostname,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${node.hostip}:${node.port}'
                    '${node.pname.isNotEmpty ? ' · ${node.pname}' : ''}',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: latencyColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                latencyText,
                style: text.labelMedium?.copyWith(
                  color: latencyColor,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
