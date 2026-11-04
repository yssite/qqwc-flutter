/// 本地设置（SharedPreferences）与历史记录（JSON 文件）持久化。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/protocol.dart';
import '../engine/models.dart';

class AppSettings {
  AppSettings({
    this.autoMatch = true,
    this.province = '',
    this.city = '',
    this.oper = '',
    this.durationSec = 8,
    this.downThreads = 8,
    this.upThreads = 4,
    this.skipUpload = false,
    this.ipv6 = false,
    this.deviceId = '',
    this.model = 'Android',
    this.autoLocate = true,
    this.permissionsAsked = false,
    this.verboseLog = false,
    this.schema = 3,
    this.autoCheckUpdate = true,
    this.useUpdateMirror = false,
    this.lastUpdateCheck = 0,
  });

  bool autoMatch;
  String province;
  String city;
  String oper;
  int durationSec;
  int downThreads;
  int upThreads;
  bool skipUpload;
  bool ipv6;
  String deviceId;
  String model;

  /// 允许用定位省份匹配节点（运营商仍按出口 IP 判断）
  bool autoLocate;

  /// 是否已经弹过权限说明，避免每次启动都打扰
  bool permissionsAsked;

  /// 详细日志：额外记录每次链路快照、原生诊断与采样明细
  bool verboseLog;

  /// 启动时自动检查 GitHub 更新
  bool autoCheckUpdate;

  /// 上次检查更新时间（epoch 秒），用于避免每次启动都请求 GitHub
  int lastUpdateCheck;

  /// 下载更新时优先走镜像（GitHub 直连不通时用）
  bool useUpdateMirror;

  /// 设置结构版本，用于一次性迁移（v2：清掉旧版误存的自动运营商）
  int schema;

  Map<String, dynamic> toJson() => {
    'autoMatch': autoMatch,
    'province': province,
    'city': city,
    'oper': oper,
    'durationSec': durationSec,
    'downThreads': downThreads,
    'upThreads': upThreads,
    'skipUpload': skipUpload,
    'ipv6': ipv6,
    'deviceId': deviceId,
    'model': model,
    'autoLocate': autoLocate,
    'permissionsAsked': permissionsAsked,
    'verboseLog': verboseLog,
    'autoCheckUpdate': autoCheckUpdate,
    'useUpdateMirror': useUpdateMirror,
    'lastUpdateCheck': lastUpdateCheck,
    'schema': schema,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    autoMatch: j['autoMatch'] as bool? ?? true,
    province: '${j['province'] ?? ''}',
    city: '${j['city'] ?? ''}',
    oper: '${j['oper'] ?? ''}',
    durationSec: (j['durationSec'] as num?)?.toInt() ?? 8,
    downThreads: (j['downThreads'] as num?)?.toInt() ?? 8,
    upThreads: (j['upThreads'] as num?)?.toInt() ?? 4,
    skipUpload: j['skipUpload'] as bool? ?? false,
    ipv6: j['ipv6'] as bool? ?? false,
    deviceId: '${j['deviceId'] ?? ''}',
    model: '${j['model'] ?? 'Android'}',
    autoLocate: j['autoLocate'] as bool? ?? true,
    permissionsAsked: j['permissionsAsked'] as bool? ?? false,
    verboseLog: j['verboseLog'] as bool? ?? false,
    autoCheckUpdate: j['autoCheckUpdate'] as bool? ?? true,
    useUpdateMirror: j['useUpdateMirror'] as bool? ?? false,
    lastUpdateCheck: (j['lastUpdateCheck'] as num?)?.toInt() ?? 0,
    // 旧数据没有该字段 → 0，触发下面的迁移（清掉旧版自动写入的运营商）
    schema: (j['schema'] as num?)?.toInt() ?? 0,
  );
}

class SettingsStore {
  SettingsStore._();

  static const _key = 'app_settings_v1';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    AppSettings settings;
    if (raw == null) {
      settings = AppSettings();
    } else {
      try {
        settings = AppSettings.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      } catch (_) {
        settings = AppSettings();
      }
    }
    if (settings.deviceId.isEmpty) {
      settings.deviceId = 'TS${randomHex(16)}';
      await save(settings);
    }
    // v3：旧版本会把「出口 IP 识别出的运营商」写回偏好，切卡后一直沿用旧运营商。
    // 升级时清掉一次（无论之前是 schema 0 还是 2），让运营商重新跟随数据卡 / 用户手动选择。
    if (settings.schema < 3) {
      settings.oper = '';
      settings.schema = 3;
      await save(settings);
    }
    return settings;
  }

  static Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}

class HistoryStore {
  HistoryStore._();

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/history.json');
  }

  static Future<List<TestRecord>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      final list = jsonDecode(text) as List<dynamic>;
      return list
          .map((e) => TestRecord.fromJson((e as Map).cast<String, dynamic>()))
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<TestRecord> records) async {
    try {
      final file = await _file();
      final text = jsonEncode(
        records.map((e) => e.toJson()).toList(growable: false),
      );
      await file.writeAsString(text, flush: true);
    } catch (_) {
      // 存储失败不阻塞测速
    }
  }

  static Future<String> exportCsv(List<TestRecord> records) async {
    final sb = StringBuffer();
    sb.writeln(
      'time,node,ip,port,isp,ping_ms,jitter_ms,loss_pct,'
      'down_avg_mbps,down_max_mbps,up_avg_mbps,up_max_mbps,score,grade',
    );
    for (final r in records) {
      sb.writeln(
        [
          r.timeText,
          _csv(r.node.hostname),
          r.node.hostip,
          r.node.port,
          _csv(r.node.oper),
          r.ping.avg.toStringAsFixed(2),
          r.ping.jitter.toStringAsFixed(2),
          r.ping.loss.toStringAsFixed(0),
          r.down.avg.toStringAsFixed(2),
          r.down.max.toStringAsFixed(2),
          r.up.avg.toStringAsFixed(2),
          r.up.max.toStringAsFixed(2),
          '${r.score}',
          _csv(r.grade),
        ].join(','),
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/globalspeed_history_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(sb.toString(), flush: true);
    return file.path;
  }

  static String _csv(String value) => value.contains(',') || value.contains('"')
      ? '"${value.replaceAll('"', '""')}"'
      : value;
}

/// 出口 IP / 归属地 / 运营商识别（与桌面版一致：ip-api → cip.cc → ipify）
class NetInfoService {
  NetInfoService._();

  static String operOf(String isp) {
    final s = isp.replaceAll(' ', '');
    final upper = s.toUpperCase();
    if (s.contains('电信') ||
        upper.contains('CHINANET') ||
        upper.contains('CHINA TELECOM')) {
      return '电信';
    }
    if (s.contains('联通') ||
        s.contains('网通') ||
        upper.contains('UNICOM') ||
        upper.contains('CHINA169')) {
      return '联通';
    }
    if (s.contains('移动') ||
        upper.contains('CHINAMOBILE') ||
        upper.contains('CMNET') ||
        upper.contains('MOBILE')) {
      return '移动';
    }
    if (s.contains('教育') || upper.contains('CERNET')) return '教育网';
    if (s.contains('广电') || upper.contains('BROADCAST')) return '广电网';
    return '';
  }

  /// SIM 卡名 → 测速节点口径的运营商。
  /// 广电（46015）借用移动的基站与核心网，节点按移动匹配即可。
  static String simOperOf(String simName) {
    final s = simName.replaceAll(' ', '');
    if (s.isEmpty) return '';
    if (s.contains('广电') || s.toUpperCase().contains('BROADCAST')) return '移动';
    return operOf(simName);
  }

  static Future<NetInfo> detect() async {
    try {
      final map = await HttpText.getJson(
        'http://ip-api.com/json/?lang=zh-CN',
        timeout: const Duration(seconds: 5),
      );
      if (map != null && '${map['query'] ?? ''}'.isNotEmpty) {
        return NetInfo(
          ip: '${map['query']}',
          country: '${map['country'] ?? ''}',
          province: '${map['regionName'] ?? ''}',
          city: '${map['city'] ?? ''}',
          isp: '${map['isp'] ?? ''}',
          oper: operOf('${map['isp'] ?? ''}'),
        );
      }
    } catch (_) {}
    try {
      final text = await HttpText.get(
        'https://api.ipify.org',
        timeout: const Duration(seconds: 5),
      );
      final ip = text.trim();
      if (ip.contains('.')) return NetInfo(ip: ip);
    } catch (_) {}
    return const NetInfo();
  }

  static Future<String> localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address != '0.0.0.0') {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '';
  }
}

/// 诊断项结果
class DiagResult {
  DiagResult({
    required this.title,
    required this.subtitle,
    this.value = '',
    this.ok = true,
    this.details = const [],
  });

  final String title;
  final String subtitle;
  final String value;
  final bool ok;
  final List<String> details;
}
