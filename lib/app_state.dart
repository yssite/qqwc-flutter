/// 应用状态：设置、节点库、历史、网络信息与测速会话的编排。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_log.dart';
import '../core/node.dart';
import '../data/link_service.dart';
import '../data/store.dart';
import '../data/update_service.dart';
import '../engine/engine_controller.dart';
import '../engine/models.dart';

/// 当前（或最近一次）测速的实时状态
class LiveTest {
  TestPhase phase = TestPhase.idle;
  String? note;
  Node? node;
  int candidateCount = 0;
  PingStat ping = const PingStat();
  double dnsMs = 0;

  final List<Sample> downSamples = [];
  final List<Sample> upSamples = [];
  SpeedPhase? downResult;
  SpeedPhase? upResult;

  double liveSpeed = 0;
  bool liveUpload = false;
  int elapsedMs = 0;

  TestRecord? result;
  String? error;

  bool get isRunning => phase.isRunning;

  void reset() {
    phase = TestPhase.idle;
    note = null;
    ping = const PingStat();
    dnsMs = 0;
    downSamples.clear();
    upSamples.clear();
    downResult = null;
    upResult = null;
    liveSpeed = 0;
    liveUpload = false;
    elapsedMs = 0;
    result = null;
    error = null;
  }
}

class AppState extends ChangeNotifier {
  AppState._(this.settings);

  static Future<AppState> create() async {
    final settings = await SettingsStore.load();
    await AppLog.init(verbose: settings.verboseLog);
    final state = AppState._(settings);
    await state._bootstrap();
    return state;
  }

  AppSettings settings;
  List<Node> nodes = const [];
  List<TestRecord> history = const [];
  NetInfo netInfo = const NetInfo();
  final LiveTest live = LiveTest();
  final List<Node> recentNodes = [];

  /// 当前链路（原生采集）：网络类型、制式、频段、信号
  LinkInfo link = const LinkInfo();

  /// 定位得到的所在地（仅用于省份匹配与展示）
  GeoPlace? place;

  /// 是否已经尝试过定位（用于区分「定位中」与「定位失败」）
  bool locationTried = false;

  /// 运行时权限状态
  LinkPermissions permissions = LinkPermissions.none;

  /// 安装包版本（读 APK，设置页底部展示）
  AppVersion version = const AppVersion();

  EngineHandle? _engine;
  bool _nodesRefreshing = false;
  String? _nodesMessage;

  bool get nodesRefreshing => _nodesRefreshing;
  String? get nodesMessage => _nodesMessage;

  Future<void> _bootstrap() async {
    final results = await Future.wait<dynamic>([
      NodeRepository.bundled(),
      HistoryStore.load(),
      NetInfoService.localIp(),
      LinkService.permissions(),
      LinkService.snapshot(),
      LinkService.appVersion(),
    ]);
    nodes = results[0] as List<Node>;
    history = results[1] as List<TestRecord>;
    netInfo = NetInfo(localIp: results[2] as String);
    permissions = results[3] as LinkPermissions;
    link = results[4] as LinkInfo;
    version = results[5] as AppVersion;
    AppLog.info(
      'app',
      '启动 ${version.display} · ${settings.model} · 节点 ${nodes.length} 条',
    );
    AppLog.info(
      'perm',
      '定位=${permissions.location} 电话=${permissions.phone}',
    );
    _linkKey = _keyOf(link);
    UpdateService.instance.preferMirror = settings.useUpdateMirror;
    AppLog.info('link', _lineOf(link));
    notifyListeners();
    unawaited(refreshNetInfo());
    if (permissions.location) unawaited(refreshLocation());
    if (AppLog.verbose) unawaited(logDiagnostics(reason: 'startup'));
    _startLinkWatch();
  }

  Timer? _linkTimer;
  StreamSubscription<String>? _linkChanges;
  String _linkKey = '';

  String _keyOf(LinkInfo l) =>
      '${l.kindKey}|${l.tag}|${l.detail}|${l.operatorName}|${l.vpn}|${l.subId}';

  String _lineOf(LinkInfo l) =>
      '${l.kindKey} sub=${l.subId} ${l.operatorName} ${l.tag} | ${l.detail}';

  /// 12 秒轮询只是兜底；真正的刷新由系统回调（Wi-Fi/蜂窝切换、切卡、信号变化）即时触发。
  void _startLinkWatch() {
    _linkTimer?.cancel();
    _linkTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(refreshLink()),
    );
    LinkService.init();
    _linkChanges?.cancel();
    _linkChanges = LinkService.changes.listen((reason) {
      AppLog.debug('link', '系统回调：$reason');
      unawaited(refreshLink());
    });
  }

  Future<void> refreshLink() async {
    final next = await LinkService.snapshot();
    final key = _keyOf(next);
    if (key == _linkKey) return;
    final prev = link;
    _linkKey = key;
    link = next;
    AppLog.info('link', _lineOf(next));
    if (AppLog.verbose) unawaited(logDiagnostics(reason: 'link-change'));
    notifyListeners();
    // 换卡 / 换接入方式 / 换运营商后，出口 IP 与归属地都会变，必须重新探测，
    // 否则节点匹配会沿用上一个网络的运营商
    final netChanged = next.subId != prev.subId ||
        next.kindKey != prev.kindKey ||
        next.operatorName != prev.operatorName;
    if (netChanged && _netInfoKey != _netKeyOf(next)) {
      unawaited(refreshNetInfo());
    }
  }

  String _netKeyOf(LinkInfo l) => '${l.subId}|${l.kindKey}|${l.operatorName}';

  /// 把原生侧的双卡诊断快照写进日志（详细模式与导出时调用）。
  Future<void> logDiagnostics({String reason = ''}) async {
    try {
      final map = await LinkService.debugSnapshot();
      AppLog.info(
        'diag',
        '${reason.isEmpty ? '' : '[$reason] '}${jsonEncode(map)}',
      );
    } catch (e) {
      AppLog.warn('diag', '诊断快照获取失败：$e');
    }
  }

  /// 导出日志（设置页「导出」按钮）
  Future<File> exportLogs() async {
    await logDiagnostics(reason: 'export');
    final node = live.node;
    final header = [
      '版本 ${version.display}',
      '链路 ${_lineOf(link)}',
      '权限 定位=${permissions.location} 电话=${permissions.phone}',
      '省份 $effectiveProvince（来源 $provinceSource）· 运营商 $effectiveOper',
      '节点 ${node == null ? '-' : '${node.hostname} ${node.hostip}:${node.port}'}',
      '详细日志 ${AppLog.verbose ? '开' : '关'}',
    ].join('\n');
    final file = await AppLog.export(header: header);
    AppLog.info('log', '导出日志 ${file.path}');
    return file;
  }

  Future<void> clearLogs() async {
    await AppLog.clear();
    AppLog.info('log', '日志已清空');
    notifyListeners();
  }

  Future<void> refreshLocation() async {
    final next = await LinkService.locate();
    locationTried = true;
    if (next == null) {
      AppLog.info('geo', '定位失败');
      notifyListeners();
      return;
    }
    AppLog.info(
      'geo',
      '定位 ${next.province} ${next.city} '
          '(${next.lat.toStringAsFixed(4)},${next.lng.toStringAsFixed(4)})',
    );
    final changed =
        place?.province != next.province || place?.city != next.city;
    place = next;
    if (changed) notifyListeners();
  }

  /// 申请定位 / 电话权限，结束后刷新链路与所在地。
  Future<LinkPermissions> requestPermissions() async {
    permissions = await LinkService.requestPermissions();
    AppLog.info(
      'perm',
      '申请结果 定位=${permissions.location} 电话=${permissions.phone}',
    );
    notifyListeners();
    if (permissions.location) await refreshLocation();
    await refreshLink();
    notifyListeners();
    return permissions;
  }

  /// 匹配用的省份：定位优先，其次手动偏好，最后是 IP 归属地
  String get effectiveProvince {
    if (settings.autoLocate && (place?.province.isNotEmpty ?? false)) {
      return place!.province;
    }
    return settings.province.isNotEmpty ? settings.province : netInfo.province;
  }

  /// 运营商：蜂窝优先用数据卡的 SIM 运营商（那才是真正在跑流量的网络），
  /// Wi-Fi / 有线再退回出口 IP 识别 —— 家里宽带是电信、手机卡是联通时不会串。
  String get effectiveOper {
    if (settings.oper.isNotEmpty) return settings.oper;
    if (link.isCellular) {
      final simOper = NetInfoService.simOperOf(link.operatorName);
      if (simOper.isNotEmpty) return simOper;
    }
    if (netInfo.oper.isNotEmpty) return netInfo.oper;
    return NetInfoService.simOperOf(link.operatorName);
  }

  /// 芯片上显示的运营商文案：`电信 · 卡 2`
  String get operWithSlot {
    final oper = effectiveOper;
    final slot = link.simSlot;
    if (oper.isEmpty) return '';
    if (link.isCellular && slot >= 0) return '$oper · 卡${slot + 1}';
    return oper;
  }

  String get effectiveCity {
    if (settings.autoLocate && (place?.province.isNotEmpty ?? false)) {
      var city = place!.city.trim();
      if (city.endsWith('市')) city = city.substring(0, city.length - 1);
      if (city.isNotEmpty) return city;
    }
    return settings.city;
  }

  String get provinceSource {
    if (settings.autoLocate && (place?.province.isNotEmpty ?? false)) {
      return '定位';
    }
    if (settings.province.isNotEmpty) return '偏好设置';
    return netInfo.province.isNotEmpty ? '出口 IP' : '';
  }

  bool get locating => permissions.location && place == null;

  @override
  void dispose() {
    _linkTimer?.cancel();
    _linkChanges?.cancel();
    unawaited(disposeEngine());
    super.dispose();
  }

  /// 出口信息（IP / 归属地 / 运营商）只在探测时更新，不再写回用户偏好 ——
  /// 否则切卡后旧运营商会被当成「手动选择」一直沿用。
  String _netInfoKey = '';

  Future<void> refreshNetInfo() async {
    final info = await NetInfoService.detect();
    netInfo = info.copyWith(localIp: netInfo.localIp);
    _netInfoKey = _netKeyOf(link);
    AppLog.info(
      'net',
      '出口 ${info.ip.isEmpty ? '--' : info.ip} · '
          '${info.province}${info.city} · '
          '${info.oper.isEmpty ? info.isp : info.oper}',
    );
    notifyListeners();
  }

  Future<void> _persistSettings() => SettingsStore.save(settings);

  Future<void> updateSettings(void Function(AppSettings s) mutate) async {
    mutate(settings);
    notifyListeners();
    await _persistSettings();
  }

  Future<void> refreshNodes() async {
    if (_nodesRefreshing) return;
    _nodesRefreshing = true;
    _nodesMessage = '正在拉取节点表…';
    notifyListeners();
    try {
      final latest = await NodeRepository.fetchLatest();
      nodes = latest;
      _nodesMessage = '节点表已更新：${latest.length} 个';
    } catch (e) {
      _nodesMessage = '更新失败，继续使用内置节点表';
    } finally {
      _nodesRefreshing = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- 测速

  Future<void> startTest({Node? node}) async {
    if (live.isRunning) return;
    await disposeEngine();
    await refreshLink();
    // 链路刚换过（比如刚切卡）而出口信息还是旧的，先补一次探测再匹配节点
    if (_netInfoKey != _netKeyOf(link)) {
      await refreshNetInfo();
    }
    live.reset();
    live.phase = TestPhase.matching;
    live.node = node;
    AppLog.info(
      'test',
      '开始测速 省份=$effectiveProvince($provinceSource) 运营商=$effectiveOper '
          '链路=${link.tag} 节点=${node?.hostname ?? '自动'}',
    );
    notifyListeners();

    final request = EngineRequest(
      nodes: nodes,
      node: node,
      autoMatch: settings.autoMatch,
      province: effectiveProvince,
      city: effectiveCity,
      oper: effectiveOper,
      publicIp: netInfo.ip,
      durationSec: settings.durationSec,
      downThreads: settings.downThreads,
      upThreads: settings.upThreads,
      skipUpload: settings.skipUpload,
      model: settings.model,
      imei: settings.deviceId,
      localIp: netInfo.localIp,
      netTag: link.recordTag,
      netKind: link.kindKey,
    );

    try {
      final handle = await SpeedEngine.start(request);
      _engine = handle;
      final sub = handle.events.listen(_onEvent);
      _engineSubscription = sub;
      if (node != null) _rememberNode(node);
    } catch (e, st) {
      live.phase = TestPhase.failed;
      live.error = '引擎启动失败：$e';
      AppLog.error('test', '引擎启动失败', e, st);
      notifyListeners();
    }
  }

  StreamSubscription<EngineEvent>? _engineSubscription;

  void _onEvent(EngineEvent event) {
    switch (event) {
      case EnginePhase(:final phase, :final note):
        live.phase = phase;
        live.note = note;
        AppLog.info('test', '阶段 ${phase.name}${note == null ? '' : ' · $note'}');
        if (phase == TestPhase.download) {
          live.liveUpload = false;
          live.liveSpeed = 0;
        } else if (phase == TestPhase.upload) {
          live.liveUpload = true;
          live.liveSpeed = 0;
        }
      case EngineNode(:final node, :final candidates):
        live.node = node;
        live.candidateCount = candidates;
        _rememberNode(node);
        AppLog.info(
          'test',
          '选中节点 ${node.hostname} ${node.hostip}:${node.port} '
              '(候选 $candidates)',
        );
      case EnginePing(:final ping, :final dnsMs):
        live.ping = ping;
        live.dnsMs = dnsMs;
        AppLog.info(
          'test',
          '延迟 ${ping.avg.toStringAsFixed(1)}ms 抖动 ${ping.jitter.toStringAsFixed(1)}ms '
              '丢包 ${ping.loss.toStringAsFixed(0)}% DNS ${dnsMs.toStringAsFixed(1)}ms',
        );
      case EngineSample(:final upload, :final sample):
        if (upload) {
          live.upSamples.add(sample);
          live.liveUpload = true;
        } else {
          live.downSamples.add(sample);
          live.liveUpload = false;
        }
        live.liveSpeed = sample.speed;
        live.elapsedMs = sample.elapsedMs;
        AppLog.debug(
          'test',
          '${upload ? '上行' : '下行'}采样 ${sample.speed.toStringAsFixed(1)}Mbps '
              '@${sample.elapsedMs}ms',
        );
      case EnginePhaseResult(:final upload, :final phase):
        if (upload) {
          live.upResult = phase;
        } else {
          live.downResult = phase;
        }
        live.liveSpeed = 0;
        AppLog.info(
          'test',
          '${upload ? '上行' : '下行'}完成 avg=${phase.avg.toStringAsFixed(1)} '
              'max=${phase.max.toStringAsFixed(1)} 采样=${phase.samples.length}',
        );
      case EngineDone(:final record):
        live.result = record;
        live.phase = TestPhase.done;
        live.liveSpeed = 0;
        AppLog.info(
          'test',
          '完成 下行=${record.down.avg.toStringAsFixed(1)} '
              '上行=${record.up.avg.toStringAsFixed(1)} 评分=${record.score}'
              '${record.grade} 链路=${record.netTag}',
        );
        _pushHistory(record);
        HapticFeedback.mediumImpact();
        unawaited(disposeEngine());
      case EngineFailure(:final message):
        live.phase = TestPhase.failed;
        live.error = message;
        live.liveSpeed = 0;
        AppLog.error('test', '测速失败：$message');
        HapticFeedback.heavyImpact();
        unawaited(disposeEngine());
      case EngineCanceled():
        live.phase = TestPhase.canceled;
        live.liveSpeed = 0;
        AppLog.info('test', '用户取消');
        unawaited(disposeEngine());
    }
    notifyListeners();
  }

  void stopTest() {
    _engine?.cancel();
  }

  Future<void> disposeEngine() async {
    await _engineSubscription?.cancel();
    _engineSubscription = null;
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }

  void _rememberNode(Node node) {
    recentNodes.removeWhere((n) => n.key == node.key);
    recentNodes.insert(0, node);
    if (recentNodes.length > 6) recentNodes.removeLast();
  }

  Future<void> _pushHistory(TestRecord record) async {
    history = [record, ...history].take(500).toList(growable: false);
    await HistoryStore.save(history);
  }

  Future<void> deleteRecord(String id) async {
    history = history.where((r) => r.id != id).toList(growable: false);
    notifyListeners();
    await HistoryStore.save(history);
  }

  Future<void> clearHistory() async {
    history = const [];
    notifyListeners();
    await HistoryStore.save(history);
  }

  Future<String> exportHistory() => HistoryStore.exportCsv(history);

  // ---------------------------------------------------------------- 诊断 / 批量探测

  /// 批量 TCP 握手延迟探测（8 并发），回调返回 index → ms。
  Future<Map<int, double>> probeNodes(
    List<Node> list, {
    int concurrency = 8,
    void Function(int done, int total)? onProgress,
  }) async {
    final result = <int, double>{};
    var cursor = 0;
    var done = 0;
    final total = list.length;

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= total) return;
        final node = list[index];
        final ms = await _tcpProbe(node.hostip, node.portNum);
        result[index] = ms;
        done++;
        onProgress?.call(done, total);
      }
    }

    await Future.wait(
      List.generate(math.min(concurrency, math.max(total, 1)), (_) => worker()),
    );
    return result;
  }

  Future<double> _tcpProbe(String host, int port) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 1200),
      );
      sw.stop();
      socket.destroy();
      return (sw.elapsedMicroseconds / 1000.0 * 100).round() / 100;
    } catch (_) {
      return -1;
    }
  }

  /// 诊断：对目标做 N 次 TCP RTT
  Future<PingStat> diagPing(String host, int port, {int count = 5}) async {
    final samples = <double>[];
    var ok = 0;
    for (var i = 0; i < count; i++) {
      final ms = await _tcpProbe(host, port);
      if (ms >= 0) {
        samples.add(ms);
        ok++;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (samples.isEmpty) {
      return PingStat(loss: 100);
    }
    final avg = samples.reduce((a, b) => a + b) / samples.length;
    var jitter = 0.0;
    if (samples.length > 1) {
      var sum = 0.0;
      for (var i = 1; i < samples.length; i++) {
        sum += (samples[i] - samples[i - 1]).abs();
      }
      jitter = sum / (samples.length - 1);
    }
    return PingStat(
      avg: (avg * 100).round() / 100,
      min: samples.reduce(math.min),
      max: samples.reduce(math.max),
      jitter: (jitter * 100).round() / 100,
      loss: 100.0 * (count - ok) / count,
      samples: samples,
    );
  }

  Future<DiagResult> diagDns(String host) async {
    final sw = Stopwatch()..start();
    try {
      final addrs = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      sw.stop();
      final ms = (sw.elapsedMicroseconds / 1000.0 * 100).round() / 100;
      final list = addrs.map((a) => a.address).toSet().toList();
      return DiagResult(
        title: 'DNS 解析',
        subtitle: host,
        value: '${ms.toStringAsFixed(1)} ms',
        details: list,
        ok: true,
      );
    } catch (e) {
      return DiagResult(
        title: 'DNS 解析',
        subtitle: host,
        value: '解析失败',
        ok: false,
      );
    }
  }

  Future<List<DiagResult>> diagReachability() async {
    const targets = <(String, String, int)>[
      ('北京联通', '61.135.214.54', 65499),
      ('上海电信', '124.74.52.254', 65499),
      ('广州移动', '120.196.0.1', 65499),
      ('腾讯云', '119.29.29.29', 443),
      ('阿里 DNS', '223.5.5.5', 443),
    ];
    final results = <DiagResult>[];
    for (final (name, host, port) in targets) {
      final sw = Stopwatch()..start();
      final ms = await _tcpProbe(host, port);
      sw.stop();
      results.add(
        DiagResult(
          title: name,
          subtitle: '$host:$port',
          value: ms < 0 ? '不可达' : '${ms.toStringAsFixed(0)} ms',
          ok: ms >= 0,
        ),
      );
    }
    return results;
  }
}
