/// 当前链路信息（网络类型 / 制式 / 频段 / 信号）与定位省份。
///
/// 数据由 Android 原生侧 `NetLink.kt` 通过 `globalspeed/netlink` 通道提供；
/// 任何字段拿不到时保持默认值，由 UI 决定是否隐藏，绝不影响测速主流程。
library;

import 'package:flutter/services.dart';

import 'province_geo.dart';

enum LinkKind { wifi, cellular, ethernet, vpn, other, none }

class WifiLink {
  const WifiLink({
    this.freqMhz = 0,
    this.rssi = 0,
    this.linkSpeed = 0,
    this.standard = '',
    this.bandwidthMhz = 0,
  });

  final int freqMhz;
  final int rssi;
  final int linkSpeed;
  final String standard;
  final int bandwidthMhz;

  /// 频段简写：2.4G / 5G / 6G
  String get bandLabel {
    if (freqMhz >= 5925) return '6G';
    if (freqMhz >= 4900) return '5G';
    if (freqMhz >= 2400) return '2.4G';
    return '';
  }

  /// 频段全写：2.4GHz / 5GHz / 6GHz
  String get freqLabel => bandLabel.isEmpty ? '' : '${bandLabel}Hz';
}

class CellLink {
  const CellLink({
    this.networkType = 0,
    this.nr = false,
    this.nrBand = '',
    this.lteBand = '',
    this.rsrp = 0,
    this.sinr = 0,
    this.lteBandwidthMhz = 0,
    this.nrBandwidthMhz = 0,
  });

  final int networkType;
  final bool nr;
  final String nrBand;
  final String lteBand;
  final int rsrp;
  final int sinr;
  final int lteBandwidthMhz;

  /// 5G 频宽：公开 API 多数平台给不出来（高通尤甚），拿不到就是 0
  final int nrBandwidthMhz;

  String get generation {
    if (nr || networkType == 20) return '5G';
    if (networkType >= 13) return '4G';
    if (networkType >= 3) return '3G';
    if (networkType >= 1) return '2G';
    return '';
  }

  String get bandLabel => nrBand.isNotEmpty ? nrBand : lteBand;

  /// 4G / Wi-Fi 的频宽是可读的；5G 拿不到就返回 0（UI 隐藏这一段）
  int get bandwidthMhz => nr ? nrBandwidthMhz : lteBandwidthMhz;
}

class LinkInfo {
  const LinkInfo({
    this.kind = LinkKind.none,
    this.vpn = false,
    this.metered = false,
    this.subId = -1,
    this.simSlot = -1,
    this.operatorName = '',
    this.wifi,
    this.cell,
  });

  final LinkKind kind;
  final bool vpn;
  final bool metered;

  /// 原生侧最终选中的数据卡 subscriptionId，用于日志排查双卡问题
  final int subId;

  /// 数据卡所在卡槽（0 基），-1 未知
  final int simSlot;

  final String operatorName;
  final WifiLink? wifi;
  final CellLink? cell;

  bool get isWifi => kind == LinkKind.wifi;

  bool get isCellular => kind == LinkKind.cellular;

  bool get isEmpty => kind == LinkKind.none;

  /// 首页右上角的简写：`5G n41`、`5G WiFi6`、`有线网络`
  String get tag {
    switch (kind) {
      case LinkKind.wifi:
        final band = wifi?.bandLabel ?? '';
        final std = wifi?.standard ?? '';
        if (std.isEmpty) return band.isEmpty ? 'WiFi' : '$band WiFi';
        return band.isEmpty ? std : '$band $std';
      case LinkKind.cellular:
        final gen = cell?.generation ?? '';
        final band = cell?.bandLabel ?? '';
        if (gen.isEmpty) return band.isEmpty ? '移动网络' : band;
        return band.isEmpty ? gen : '$gen $band';
      case LinkKind.ethernet:
        return '有线网络';
      case LinkKind.vpn:
        return 'VPN';
      case LinkKind.other:
        return '已联网';
      case LinkKind.none:
        return '';
    }
  }

  /// 诊断页的连接情况：`5G n41 -77 RSRP`、`WiFi6 5GHz 160MHz -60 RSSI`
  String get detail {
    switch (kind) {
      case LinkKind.wifi:
        final w = wifi;
        if (w == null) return tag;
        final head = [w.standard, w.freqLabel].where((e) => e.isNotEmpty).join(' ');
        final parts = <String>[
          if (head.isNotEmpty) head,
          if (w.bandwidthMhz > 0) '${w.bandwidthMhz}MHz',
          if (w.rssi < 0) '${w.rssi} RSSI',
        ];
        return parts.isEmpty ? tag : parts.join(' ');
      case LinkKind.cellular:
        final c = cell;
        if (c == null) return tag;
        final head = [c.generation, c.bandLabel]
            .where((e) => e.isNotEmpty)
            .join(' ');
        final parts = <String>[
          if (head.isNotEmpty) head,
          if (c.bandwidthMhz > 0) '${c.bandwidthMhz}MHz',
          if (c.rsrp < 0) '${c.rsrp} RSRP',
        ];
        return parts.isEmpty ? tag : parts.join(' ');
      default:
        return tag;
    }
  }

  /// 结果入库用的短标签（`5G n41` / `5G WiFi6`）
  String get recordTag => tag;

  /// 网络大类，用于结果页选图标
  String get kindKey => switch (kind) {
        LinkKind.wifi => 'wifi',
        LinkKind.cellular => 'cell',
        LinkKind.ethernet => 'lan',
        LinkKind.vpn => 'vpn',
        _ => '',
      };

  static LinkInfo fromMap(Map<String, dynamic> map) {
    final kind = switch ('${map['type'] ?? 'none'}') {
      'wifi' => LinkKind.wifi,
      'cellular' => LinkKind.cellular,
      'ethernet' => LinkKind.ethernet,
      'vpn' => LinkKind.vpn,
      'none' => LinkKind.none,
      _ => LinkKind.other,
    };
    final wifiMap = map['wifi'];
    final cellMap = map['cell'];
    return LinkInfo(
      kind: kind,
      vpn: map['vpn'] == true,
      metered: map['metered'] == true,
      subId: (map['subId'] as num?)?.toInt() ?? -1,
      simSlot: (map['simSlot'] as num?)?.toInt() ?? -1,
      operatorName: '${map['operatorName'] ?? ''}',
      wifi: wifiMap is Map
          ? WifiLink(
              freqMhz: (wifiMap['freqMhz'] as num?)?.toInt() ?? 0,
              rssi: (wifiMap['rssi'] as num?)?.toInt() ?? 0,
              linkSpeed: (wifiMap['linkSpeed'] as num?)?.toInt() ?? 0,
              standard: '${wifiMap['standard'] ?? ''}',
              bandwidthMhz: (wifiMap['bandwidthMhz'] as num?)?.toInt() ?? 0,
            )
          : null,
      cell: cellMap is Map
          ? CellLink(
              networkType: (cellMap['networkType'] as num?)?.toInt() ?? 0,
              nr: cellMap['nr'] == true,
              nrBand: '${cellMap['nrBand'] ?? ''}',
              lteBand: '${cellMap['lteBand'] ?? ''}',
              rsrp: (cellMap['rsrp'] as num?)?.toInt() ?? 0,
              sinr: (cellMap['sinr'] as num?)?.toInt() ?? 0,
              lteBandwidthMhz:
                  (cellMap['lteBandwidthMhz'] as num?)?.toInt() ?? 0,
              nrBandwidthMhz:
                  (cellMap['nrBandwidthMhz'] as num?)?.toInt() ?? 0,
            )
          : null,
    );
  }
}

class LinkPermissions {
  const LinkPermissions({this.location = false, this.phone = false});

  final bool location;
  final bool phone;

  bool get any => location || phone;

  static const none = LinkPermissions();

  static LinkPermissions fromMap(Map<String, dynamic>? map) => LinkPermissions(
        location: map?['location'] == true,
        phone: map?['phone'] == true,
      );
}

/// 安装包版本（直接读 APK，避免和界面里写死的字符串对不上）
class AppVersion {
  const AppVersion({this.name = '', this.code = 0});

  final String name;
  final int code;

  bool get isEmpty => name.isEmpty;

  /// `v1.2.0 (12000)`
  String get display =>
      'v${name.isEmpty ? '--' : name}${code > 0 ? ' ($code)' : ''}';
}

class GeoPlace {
  const GeoPlace({
    this.lat = 0,
    this.lng = 0,
    this.province = '',
    this.city = '',
    this.accuracy = 0,
  });

  final double lat;
  final double lng;
  final String province;
  final String city;
  final double accuracy;

  bool get isEmpty => province.isEmpty && city.isEmpty && lat == 0 && lng == 0;
}

class LinkService {
  LinkService._();

  static const _channel = MethodChannel('globalspeed/netlink');

  static Future<LinkInfo> snapshot() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('snapshot');
      if (map == null) return const LinkInfo();
      return LinkInfo.fromMap(map);
    } catch (_) {
      return const LinkInfo();
    }
  }

  static Future<LinkPermissions> permissions() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('permissions');
      return LinkPermissions.fromMap(map);
    } catch (_) {
      return LinkPermissions.none;
    }
  }

  static Future<LinkPermissions> requestPermissions() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('request');
      return LinkPermissions.fromMap(map);
    } catch (_) {
      return LinkPermissions.none;
    }
  }

  static Future<AppVersion> appVersion() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('version');
      return AppVersion(
        name: '${map?['name'] ?? ''}',
        code: (map?['code'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const AppVersion();
    }
  }

  /// 双卡 / 制式相关的完整诊断快照，用于导出日志。
  static Future<Map<String, dynamic>> debugSnapshot() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('debug');
      return map ?? const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  /// 定位 → 省份。系统 Geocoder 拿不到时用离线边界兜底。
  static Future<GeoPlace?> locate() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('location');
      if (map == null) return null;
      final lat = (map['lat'] as num?)?.toDouble() ?? 0;
      final lng = (map['lng'] as num?)?.toDouble() ?? 0;
      var province = '${map['province'] ?? ''}';
      if (province.isEmpty) province = provinceOf(lat, lng);
      final place = GeoPlace(
        lat: lat,
        lng: lng,
        province: _tidyProvince(province),
        city: '${map['city'] ?? ''}',
        accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
      );
      if (place.isEmpty) return null;
      return place;
    } catch (_) {
      return null;
    }
  }

  /// Geocoder 会返回「广东省」「北京市」这类全称，节点表里是「广东」「北京」。
  static String _tidyProvince(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    for (final suffix in const ['特别行政区', '壮族自治区', '回族自治区', '维吾尔自治区', '自治区', '省', '市']) {
      if (s.endsWith(suffix)) {
        s = s.substring(0, s.length - suffix.length);
        break;
      }
    }
    return s;
  }
}
