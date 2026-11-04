/// 结果卡 / 记录详情共用的网络标签胶囊：`5G n41`、`5G WiFi6`、`有线网络`。
library;

import 'package:flutter/material.dart';

import 'common.dart';

IconData netIconFor(String kind) => switch (kind) {
  'wifi' => Icons.wifi_rounded,
  'cell' => Icons.signal_cellular_alt_rounded,
  'lan' => Icons.settings_ethernet_rounded,
  'vpn' => Icons.vpn_key_rounded,
  _ => Icons.language_rounded,
};

class NetTagPill extends StatelessWidget {
  const NetTagPill({
    super.key,
    required this.tag,
    this.kind = '',
    this.filled = false,
  });

  final String tag;
  final String kind;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return StatusPill(label: tag, icon: netIconFor(kind), filled: filled);
  }
}
