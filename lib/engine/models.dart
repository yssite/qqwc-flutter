/// 测速引擎的数据模型与事件类型（主线程 / isolate 共享，纯 Dart）。
library;

import 'dart:math' as math;

import '../core/node.dart';

enum TestPhase {
  idle,
  matching,
  ping,
  download,
  upload,
  finishing,
  done,
  failed,
  canceled;

  String get label => switch (this) {
        TestPhase.idle => '待机',
        TestPhase.matching => '匹配节点',
        TestPhase.ping => '测量延迟',
        TestPhase.download => '下行测速',
        TestPhase.upload => '上行测速',
        TestPhase.finishing => '整理结果',
        TestPhase.done => '完成',
        TestPhase.failed => '失败',
        TestPhase.canceled => '已取消',
      };

  bool get isRunning => switch (this) {
        TestPhase.matching ||
        TestPhase.ping ||
        TestPhase.download ||
        TestPhase.upload ||
        TestPhase.finishing =>
          true,
        _ => false,
      };
}

class Sample {
  const Sample({
    required this.idx,
    required this.speed,
    required this.bytes,
    required this.preheat,
    required this.elapsedMs,
  });

  final int idx;
  final double speed;
  final int bytes;
  final bool preheat;
  final int elapsedMs;

  Map<String, dynamic> toJson() => {
        'i': idx,
        's': speed,
        'b': bytes,
        'p': preheat ? 1 : 0,
        'e': elapsedMs,
      };

  factory Sample.fromJson(Map<String, dynamic> j) => Sample(
        idx: (j['i'] as num?)?.toInt() ?? 0,
        speed: (j['s'] as num?)?.toDouble() ?? 0,
        bytes: (j['b'] as num?)?.toInt() ?? 0,
        preheat: (j['p'] as num?)?.toInt() == 1,
        elapsedMs: (j['e'] as num?)?.toInt() ?? 0,
      );
}

class PingStat {
  const PingStat({
    this.avg = 0,
    this.min = 0,
    this.max = 0,
    this.jitter = 0,
    this.loss = 0,
    this.samples = const [],
  });

  final double avg;
  final double min;
  final double max;
  final double jitter;
  final double loss;
  final List<double> samples;

  Map<String, dynamic> toJson() => {
        'avg': avg,
        'min': min,
        'max': max,
        'jitter': jitter,
        'loss': loss,
        's': samples,
      };

  factory PingStat.fromJson(Map<String, dynamic> j) => PingStat(
        avg: (j['avg'] as num?)?.toDouble() ?? 0,
        min: (j['min'] as num?)?.toDouble() ?? 0,
        max: (j['max'] as num?)?.toDouble() ?? 0,
        jitter: (j['jitter'] as num?)?.toDouble() ?? 0,
        loss: (j['loss'] as num?)?.toDouble() ?? 0,
        samples: (j['s'] as List<dynamic>? ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}

class SpeedPhase {
  const SpeedPhase({
    this.avg = 0,
    this.max = 0,
    this.samples = const [],
  });

  final double avg;
  final double max;
  final List<double> samples;

  bool get hasData => samples.isNotEmpty;

  Map<String, dynamic> toJson() => {'avg': avg, 'max': max, 's': samples};

  factory SpeedPhase.fromJson(Map<String, dynamic> j) => SpeedPhase(
        avg: (j['avg'] as num?)?.toDouble() ?? 0,
        max: (j['max'] as num?)?.toDouble() ?? 0,
        samples: (j['s'] as List<dynamic>? ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}

class TestRecord {
  const TestRecord({
    required this.id,
    required this.ts,
    required this.node,
    required this.ping,
    required this.down,
    required this.up,
    required this.dnsMs,
    required this.score,
    required this.grade,
    required this.uuid,
    required this.net,
    this.netTag = '',
    this.netKind = '',
    this.oper = '',
  });

  final String id;
  final int ts;
  final Node node;
  final PingStat ping;
  final SpeedPhase down;
  final SpeedPhase up;
  final double dnsMs;
  final int score;
  final String grade;
  final String uuid;
  final String net;

  /// 测速时的链路简写，如 `5G n41`、`5G WiFi6`
  final String netTag;

  /// 链路大类：wifi / cell / lan / vpn，用于选图标
  final String netKind;

  /// 测速当时实际使用的运营商（数据卡），结果卡优先展示它
  final String oper;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts * 1000);

  String get timeText {
    final t = time;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': ts,
        'node': node.toJson(),
        'ping': ping.toJson(),
        'down': down.toJson(),
        'up': up.toJson(),
        'dns': dnsMs,
        'score': score,
        'grade': grade,
        'uuid': uuid,
        'net': net,
        'netTag': netTag,
        'netKind': netKind,
        'oper': oper,
      };

  factory TestRecord.fromJson(Map<String, dynamic> j) => TestRecord(
        id: '${j['id']}',
        ts: (j['ts'] as num).toInt(),
        node: Node.fromJson((j['node'] as Map).cast<String, dynamic>()),
        ping: PingStat.fromJson((j['ping'] as Map).cast<String, dynamic>()),
        down: SpeedPhase.fromJson((j['down'] as Map).cast<String, dynamic>()),
        up: SpeedPhase.fromJson((j['up'] as Map).cast<String, dynamic>()),
        dnsMs: (j['dns'] as num?)?.toDouble() ?? 0,
        score: (j['score'] as num?)?.toInt() ?? 0,
        grade: '${j['grade'] ?? ''}',
        uuid: '${j['uuid'] ?? ''}',
        net: '${j['net'] ?? ''}',
        netTag: '${j['netTag'] ?? ''}',
        netKind: '${j['netKind'] ?? ''}',
        oper: '${j['oper'] ?? ''}',
      );
}

/// 网络环境信息（出口 IP / 归属地 / 运营商）
class NetInfo {
  const NetInfo({
    this.ip = '',
    this.country = '',
    this.province = '',
    this.city = '',
    this.isp = '',
    this.oper = '',
    this.localIp = '',
  });

  final String ip;
  final String country;
  final String province;
  final String city;
  final String isp;
  final String oper;
  final String localIp;

  bool get isEmpty => ip.isEmpty && province.isEmpty;

  String get locationText {
    final parts = [country, province, city].where((e) => e.isNotEmpty).toList();
    return parts.join(' · ');
  }

  NetInfo copyWith({String? localIp}) => NetInfo(
        ip: ip,
        country: country,
        province: province,
        city: city,
        isp: isp,
        oper: oper,
        localIp: localIp ?? this.localIp,
      );
}

/// 一次测速的入参
class EngineRequest {
  const EngineRequest({
    required this.nodes,
    this.node,
    this.autoMatch = true,
    this.province = '北京',
    this.city = '北京',
    this.oper = '',
    this.publicIp = '',
    this.durationSec = 8,
    this.warmupMs = 2000,
    this.downThreads = 8,
    this.upThreads = 4,
    this.skipUpload = false,
    this.bandwidth = 200,
    this.model = 'Android',
    this.imei = '',
    this.localIp = '',
    this.netTag = '',
    this.netKind = '',
  });

  final List<Node> nodes;
  final Node? node;
  final bool autoMatch;
  final String province;
  final String city;
  final String oper;
  final String publicIp;
  final int durationSec;
  final int warmupMs;
  final int downThreads;
  final int upThreads;
  final bool skipUpload;
  final int bandwidth;
  final String model;
  final String imei;
  final String localIp;
  final String netTag;
  final String netKind;

  Map<String, dynamic> toMap() => {
        'nodes': nodes.map((n) => n.toCompact()).toList(growable: false),
        'node': node?.toCompact(),
        'autoMatch': autoMatch,
        'province': province,
        'city': city,
        'oper': oper,
        'publicIp': publicIp,
        'durationSec': durationSec,
        'warmupMs': warmupMs,
        'downThreads': downThreads,
        'upThreads': upThreads,
        'skipUpload': skipUpload,
        'bandwidth': bandwidth,
        'model': model,
        'imei': imei,
        'localIp': localIp,
        'netTag': netTag,
        'netKind': netKind,
      };
}

sealed class EngineEvent {
  const EngineEvent();
}

class EnginePhase extends EngineEvent {
  const EnginePhase(this.phase, {this.note});
  final TestPhase phase;
  final String? note;
}

class EngineNode extends EngineEvent {
  const EngineNode(this.node, {this.candidates = 0});
  final Node node;
  final int candidates;
}

class EnginePing extends EngineEvent {
  const EnginePing(this.ping, this.dnsMs);
  final PingStat ping;
  final double dnsMs;
}

class EngineSample extends EngineEvent {
  const EngineSample({required this.upload, required this.sample});
  final bool upload;
  final Sample sample;
}

class EnginePhaseResult extends EngineEvent {
  const EnginePhaseResult({
    required this.upload,
    required this.phase,
    required this.bytes,
  });
  final bool upload;
  final SpeedPhase phase;
  final int bytes;
}

class EngineDone extends EngineEvent {
  const EngineDone(this.record, {this.fallbackNote});
  final TestRecord record;
  final String? fallbackNote;
}

class EngineFailure extends EngineEvent {
  const EngineFailure(this.message);
  final String message;
}

class EngineCanceled extends EngineEvent {
  const EngineCanceled();
}

/// 综合评分（0-100）：下行 45、上行 25、时延 30，速率走对数刻度。
(int, String) scoreOf(double downMbps, double upMbps, double pingMs) {
  final d = (45.0 *
          math.log(1.0 + math.max(0.0, downMbps)) /
          math.log(1001.0))
      .clamp(0.0, 45.0);
  final u = (25.0 *
          math.log(1.0 + math.max(0.0, upMbps)) /
          math.log(501.0))
      .clamp(0.0, 25.0);
  final p =
      (30.0 * (1.0 - (math.max(0.0, pingMs) / 150.0).clamp(0.0, 1.0)))
          .clamp(0.0, 30.0);
  final score = (d + u + p).round().clamp(0, 100);
  final grade = switch (score) {
    >= 90 => '极佳',
    >= 75 => '优秀',
    >= 55 => '良好',
    >= 35 => '一般',
    _ => '较差',
  };
  return (score, grade);
}
