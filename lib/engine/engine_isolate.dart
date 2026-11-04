/// 测速引擎：运行在独立 isolate 里的完整链路。
///
/// 匹配节点 → TCP RTT → dovalid 会话 → 多线程下行 → 多线程上行 → 收尾。
/// 采样口径与桌面版（Rust）一致：500ms 采样、真实时间戳 1s 滑动窗口、
/// 前 2s 预热剔除、末尾半个窗口剔除。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/node.dart';
import '../core/protocol.dart';
import 'models.dart';

class _EngineError implements Exception {
  _EngineError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _CancelFlag {
  bool canceled = false;
}

class _StopFlag {
  bool value = false;
}

class _ByteCounter {
  int value = 0;
  void add(int n) => value += n;
}

/// isolate 入口：接收 start / cancel 命令，事件通过 [events] 回传。
void engineIsolateMain(SendPort events) {
  final inbox = ReceivePort();
  events.send({'t': 'port', 'port': inbox.sendPort});
  _CancelFlag? active;
  inbox.listen((raw) {
    final msg = raw as Map;
    switch (msg['cmd']) {
      case 'start':
        final flag = _CancelFlag();
        active = flag;
        unawaited(
          _run(events, (msg['req'] as Map).cast<String, dynamic>(), flag)
              .catchError((Object e) {
            events.send({'t': 'error', 'message': _humanError(e)});
          }),
        );
      case 'cancel':
        active?.canceled = true;
    }
  });
}

String _humanError(Object e) {
  if (e is _EngineError) return e.message;
  if (e is SocketException) return '网络不可达：${e.osError?.message ?? e.message}';
  if (e is TimeoutException) return '连接超时，请检查网络';
  return '$e';
}

Future<void> _run(
  SendPort out,
  Map<String, dynamic> req,
  _CancelFlag cancel,
) async {
  final nodes = (req['nodes'] as List<dynamic>)
      .map((e) => Node.fromCompact(e as List<dynamic>))
      .toList(growable: false);
  final selected = req['node'] == null
      ? null
      : Node.fromCompact((req['node'] as List<dynamic>));
  final autoMatch = req['autoMatch'] == true;
  final province = '${req['province'] ?? '北京'}';
  final city = '${req['city'] ?? province}';
  final oper = '${req['oper'] ?? ''}';
  final durationSec = (req['durationSec'] as num?)?.toInt() ?? 8;
  final warmupMs = (req['warmupMs'] as num?)?.toInt() ?? 2000;
  final downThreads = ((req['downThreads'] as num?)?.toInt() ?? 8).clamp(1, 32);
  final upThreads = ((req['upThreads'] as num?)?.toInt() ?? 4).clamp(1, 32);
  final skipUpload = req['skipUpload'] == true;
  final bandwidth = (req['bandwidth'] as num?)?.toInt() ?? 200;
  final model = '${req['model'] ?? 'Android'}';
  final imei = '${req['imei'] ?? ''}';
  final publicIp = '${req['publicIp'] ?? ''}';
  final localIp = '${req['localIp'] ?? ''}';
  final netTag = '${req['netTag'] ?? ''}';
  final netKind = '${req['netKind'] ?? ''}';

  out.send({'t': 'phase', 'phase': 'matching'});

  // ---- 1. 选节点 ----
  List<Node> ranked;
  if (selected != null) {
    ranked = [selected];
    out.send({
      't': 'node',
      'node': selected.toCompact(),
      'count': 1,
    });
  } else {
    final candidates = await _matchCandidates(
      nodes: nodes,
      autoMatch: autoMatch,
      province: province,
      city: city,
      oper: oper,
      publicIp: publicIp,
      cancel: cancel,
    );
    if (cancel.canceled) {
      out.send({'t': 'canceled'});
      return;
    }
    if (candidates.isEmpty) throw _EngineError('没有可用测速节点');
    ranked = await _rankCandidates(candidates, cancel);
    if (ranked.isEmpty) throw _EngineError('候选节点全部不可达');
    out.send({
      't': 'node',
      'node': ranked.first.toCompact(),
      'count': ranked.length,
    });
  }
  if (cancel.canceled) {
    out.send({'t': 'canceled'});
    return;
  }

  // ---- 2. 建立会话（首选失败自动切备选，最多 3 个）----
  Node? node;
  String? uuid;
  var lastError = '无候选节点';
  for (final n in ranked.take(3)) {
    if (cancel.canceled) {
      out.send({'t': 'canceled'});
      return;
    }
    try {
      uuid = await _openSession(
        host: n.hostip,
        port: n.portNum,
        model: model,
        imei: imei,
        bandwidth: bandwidth,
      );
      node = n;
      out.send({'t': 'node', 'node': n.toCompact(), 'count': ranked.length});
      break;
    } catch (e) {
      lastError = '${n.hostname.isEmpty ? n.hostip : n.hostname}：${_humanError(e)}';
    }
  }
  if (node == null || uuid == null) {
    throw _EngineError('候选节点均失败（$lastError）');
  }

  final host = node.hostip;
  final port = node.portNum;

  // ---- 3. 延迟 ----
  out.send({'t': 'phase', 'phase': 'ping'});
  final dnsMs = await _dnsMs(host);
  final ping = await _tcpRtt(host, port, count: 5, timeoutMs: 2000);
  out.send(
    {'t': 'ping', 'ping': ping.toJson(), 'dns': dnsMs},
  );
  if (cancel.canceled) {
    await _closeSession(host, port, uuid);
    out.send({'t': 'canceled'});
    return;
  }

  final durationMs = math.max(durationSec, 2) * 1000;

  // ---- 4. 下行 ----
  out.send({'t': 'phase', 'phase': 'download'});
  final down = await _transfer(
    out: out,
    host: host,
    port: port,
    path: downloadPath(uuid),
    uuid: uuid,
    upload: false,
    threads: downThreads,
    warmupMs: warmupMs,
    durationMs: durationMs,
    cancel: cancel,
  );
  out.send({
    't': 'phaseResult',
    'dir': 'down',
    'avg': down.avg,
    'max': down.max,
    'bytes': down.bytes,
    'samples': down.phase.samples,
  });
  if (cancel.canceled) {
    await _closeSession(host, port, uuid);
    out.send({'t': 'canceled'});
    return;
  }
  if (down.bytes < 64 * 1024) {
    await _closeSession(host, port, uuid);
    throw _EngineError('下行数据量过小（${down.bytes} B），节点可能已失效');
  }

  // ---- 5. 上行 ----
  var upAvg = 0.0;
  var upMax = 0.0;
  var upSamples = <double>[];
  var upBytes = 0;
  if (!skipUpload) {
    out.send({'t': 'phase', 'phase': 'upload'});
    final up = await _transfer(
      out: out,
      host: host,
      port: port,
      path: Prot.uploadPath,
      uuid: uuid,
      upload: true,
      threads: upThreads,
      warmupMs: warmupMs,
      durationMs: durationMs,
      cancel: cancel,
    );
    upAvg = up.avg;
    upMax = up.max;
    upSamples = up.phase.samples;
    upBytes = up.bytes;
    out.send({
      't': 'phaseResult',
      'dir': 'up',
      'avg': upAvg,
      'max': upMax,
      'bytes': upBytes,
      'samples': upSamples,
    });
  }

  // ---- 6. 收尾 ----
  out.send({'t': 'phase', 'phase': 'finishing'});
  await _closeSession(host, port, uuid);

  final (score, grade) = scoreOf(down.avg, upAvg, ping.avg);
  final ts = nowSecs();
  final record = TestRecord(
    id: '$ts-${randomHex(6)}',
    ts: ts,
    node: node,
    ping: ping,
    down: down.phase,
    up: SpeedPhase(avg: _round2(upAvg), max: _round2(upMax), samples: upSamples),
    dnsMs: dnsMs,
    score: score,
    grade: grade,
    uuid: uuid,
    net: localIp,
    netTag: netTag,
    netKind: netKind,
    oper: oper,
  );
  out.send({'t': 'done', 'record': record.toJson()});
  out.send({'t': 'phase', 'phase': 'done'});
}

// ---------------------------------------------------------------------------
// 节点匹配
// ---------------------------------------------------------------------------

Future<List<Node>> _matchCandidates({
  required List<Node> nodes,
  required bool autoMatch,
  required String province,
  required String city,
  required String oper,
  required String publicIp,
  required _CancelFlag cancel,
}) async {
  final matched = <Node>[];
  if (autoMatch) {
    var ip = publicIp;
    if (ip.isEmpty) ip = await _publicIp() ?? '';
    try {
      final uri = '${Prot.base}/dataServer/mobilematch_many.php'
          '?ip=${percentEncode(ip)}&network=5'
          '&province=${percentEncode(province)}'
          '&city=${percentEncode(city)}'
          '&wifioper=${percentEncode(oper)}'
          '&mobileoperid=0&ipv6=0&model=Android&pkg=${Prot.pkgName}';
      final text = await HttpText.get(uri, timeout: const Duration(seconds: 12));
      final arr = jsonDecode(text) as List<dynamic>;
      for (final item in arr) {
        final map = (item as Map).cast<String, dynamic>();
        final ipAddr = '${map['hostip'] ?? ''}';
        if (ipAddr.isEmpty) continue;
        matched.add(Node(
          cityid: '',
          geoid: '',
          hostid: '${map['hostid'] ?? ''}',
          hostip: ipAddr,
          hostname: '${map['hostname'] ?? ''}',
          location: '${map['city'] ?? ''}',
          oper: oper,
          pname: '${map['pname'] ?? ''}',
          port: '${map['port'] ?? '65499'}',
        ));
      }
    } catch (_) {
      // 匹配接口不可用时退回内置节点表
    }
  }
  if (cancel.canceled) return const [];
  if (matched.isNotEmpty) return matched;
  return NodeRepository.localCandidates(nodes, province: province, oper: oper);
}

Future<List<Node>> _rankCandidates(List<Node> candidates, _CancelFlag cancel) async {
  final probe = candidates.take(6).toList(growable: false);
  final scored = await Future.wait(probe.map((n) async {
    final stat = await _tcpRtt(n.hostip, n.portNum, count: 2, timeoutMs: 1200);
    return (stat.avg > 0 ? stat.avg : 9999.0, n);
  }));
  scored.sort((a, b) => a.$1.compareTo(b.$1));
  final reachable = scored.where((e) => e.$1 < 9000).toList();
  if (reachable.isEmpty) return const [];
  // 首选 + 备选，最多 3 个
  return reachable.take(3).map((e) => e.$2).toList(growable: false);
}

Future<String?> _publicIp() async {
  try {
    final map = await HttpText.getJson('http://ip-api.com/json/?lang=zh-CN',
        timeout: const Duration(seconds: 5));
    final ip = map?['query'];
    if (ip is String && ip.split('.').length == 4) return ip;
  } catch (_) {}
  try {
    final text =
        await HttpText.get('https://api.ipify.org', timeout: const Duration(seconds: 5));
    final ip = text.trim();
    if (ip.split('.').length == 4) return ip;
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// 会话
// ---------------------------------------------------------------------------

Future<String> _openSession({
  required String host,
  required int port,
  required String model,
  required String imei,
  required int bandwidth,
}) async {
  final t = nowSecs();
  final token = speedToken(model: model, imei: imei, time: t, bandwidth: bandwidth);
  final path = sessionPath(
    bandwidth: bandwidth,
    model: model,
    imei: imei,
    time: t,
    token: token,
  );
  final response = await _rawHttpGet(host, port, path,
      timeout: const Duration(seconds: 8));
  final text = response.trim();
  if (text.length > 2 && text.startsWith('1')) {
    return text.substring(2).trim();
  }
  throw _EngineError('节点拒绝会话：${text.isEmpty ? '空响应' : text}');
}

Future<void> _closeSession(String host, int port, String uuid) async {
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: const Duration(seconds: 4));
    socket.write('POST ${Prot.sessionPath}?key=$uuid HTTP/1.1\r\n'
        'Host: ${hostHeader(host)}:$port\r\n'
        'Connection: close\r\n'
        'Content-Length: 0\r\n\r\n');
    await socket.flush().timeout(const Duration(seconds: 2), onTimeout: () {});
    // 不等待响应体，交给 destroy
  } catch (_) {
    // 收尾失败不影响结果
  } finally {
    socket?.destroy();
  }
}

/// 原始 socket 的 HTTP GET（会话接口返回体可能带 chunked）
Future<String> _rawHttpGet(String host, int port, String path,
    {required Duration timeout}) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  final buffer = <int>[];
  final done = Completer<void>();
  try {
    socket.write('GET $path HTTP/1.1\r\n'
        'Accept: */*\r\n'
        'Connection: close\r\n'
        'User-Agent: ${Prot.uaDownload}\r\n'
        'Host: ${hostHeader(host)}:$port\r\n\r\n');
    unawaited(socket.flush().catchError((_) {}));
    socket.listen(
      (data) {
        if (buffer.length < 262144) buffer.addAll(data);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (_) {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future.timeout(timeout, onTimeout: () {});
  } finally {
    socket.destroy();
  }
  final text = latin1.decode(buffer, allowInvalid: true);
  final split = text.indexOf('\r\n\r\n');
  final head = split < 0 ? '' : text.substring(0, split).toLowerCase();
  final body = split < 0 ? text : text.substring(split + 4);
  if (head.contains('transfer-encoding: chunked')) return _dechunk(body);
  return body;
}

String _dechunk(String body) {
  final sb = StringBuffer();
  var i = 0;
  while (i < body.length) {
    final lineEnd = body.indexOf('\r\n', i);
    if (lineEnd < 0) break;
    final sizeText = body.substring(i, lineEnd).split(';').first.trim();
    final size = int.tryParse(sizeText, radix: 16);
    if (size == null || size == 0) break;
    final start = lineEnd + 2;
    final end = math.min(start + size, body.length);
    sb.write(body.substring(start, end));
    i = end + 2;
  }
  return sb.toString();
}

// ---------------------------------------------------------------------------
// RTT / DNS
// ---------------------------------------------------------------------------

Future<PingStat> _tcpRtt(String host, int port,
    {required int count, required int timeoutMs}) async {
  final samples = <double>[];
  var ok = 0;
  for (var i = 0; i < count; i++) {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port,
          timeout: Duration(milliseconds: timeoutMs));
      sw.stop();
      samples.add(_round2(sw.elapsedMicroseconds / 1000.0));
      ok++;
      socket.destroy();
    } catch (_) {
      // 丢包
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  final loss = 100.0 * (count - ok) / count;
  if (samples.isEmpty) return PingStat(loss: loss);
  final avg = samples.reduce((a, b) => a + b) / samples.length;
  final min = samples.reduce(math.min);
  final max = samples.reduce(math.max);
  var jitter = 0.0;
  if (samples.length > 1) {
    var sum = 0.0;
    for (var i = 1; i < samples.length; i++) {
      sum += (samples[i] - samples[i - 1]).abs();
    }
    jitter = sum / (samples.length - 1);
  }
  return PingStat(
    avg: _round2(avg),
    min: _round2(min),
    max: _round2(max),
    jitter: _round2(jitter),
    loss: loss,
    samples: samples,
  );
}

Future<double> _dnsMs(String host) async {
  final sw = Stopwatch()..start();
  try {
    await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
    sw.stop();
    return _round2(sw.elapsedMicroseconds / 1000.0);
  } catch (_) {
    return -1;
  }
}

// ---------------------------------------------------------------------------
// 上下行传输 + 采样
// ---------------------------------------------------------------------------

class _TransferResult {
  _TransferResult(this.phase, this.bytes);
  final SpeedPhase phase;
  final int bytes;

  double get avg => phase.avg;
  double get max => phase.max;
}

Future<_TransferResult> _transfer({
  required SendPort out,
  required String host,
  required int port,
  required String path,
  required String uuid,
  required bool upload,
  required int threads,
  required int warmupMs,
  required int durationMs,
  required _CancelFlag cancel,
}) async {
  final counter = _ByteCounter();
  final stop = _StopFlag();
  final sockets = <Socket>[];
  final seed = DateTime.now().microsecondsSinceEpoch;
  final block = Uint8List(64 * 1024);
  fillRandomBytes(block, seed);

  final workers = List<Future<void>>.generate(
    threads,
    (i) => upload
        ? _uploadWorker(
            host: host,
            port: port,
            uuid: uuid,
            counter: counter,
            stop: stop,
            sockets: sockets,
            block: block,
            seed: seed + i,
          )
        : _downloadWorker(
            host: host,
            port: port,
            path: path,
            counter: counter,
            stop: stop,
            sockets: sockets,
          ),
  );

  final sw = Stopwatch()..start();
  final history = <(double, int)>[];
  final samples = <double>[];
  var maxSpeed = 0.0;
  var idx = 0;
  final totalMs = warmupMs + durationMs;

  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final elapsedMs = sw.elapsedMicroseconds / 1000.0;
    final elapsedSec = elapsedMs / 1000.0;
    final total = counter.value;
    history.add((elapsedSec, total));

    final cutoff = elapsedSec - 1.0;
    var base = history.first;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].$1 <= cutoff) {
        base = history[i];
        break;
      }
    }
    final span = math.max(elapsedSec - base.$1, 0.2);
    final speed = (total - base.$2) * 8.0 / span / 1e6;
    idx++;
    final preheat = elapsedMs <= warmupMs;
    if (!preheat) {
      samples.add(_round2(speed));
      if (speed > maxSpeed) maxSpeed = speed;
    }
    out.send({
      't': 'sample',
      'dir': upload ? 'up' : 'down',
      'i': idx,
      'speed': _round2(speed),
      'bytes': total,
      'p': preheat,
      'e': elapsedMs.round(),
    });
    if (elapsedMs >= totalMs || cancel.canceled) break;
  }

  stop.value = true;
  // 复制一份再遍历：worker 在 finally 里会把自己从 sockets 摘掉
  for (final s in List<Socket>.of(sockets)) {
    try {
      s.destroy();
    } catch (_) {}
  }
  await Future.wait(workers).timeout(const Duration(seconds: 3), onTimeout: () => const []);

  // 掐头去尾：预热已在采集时剔除，这里再去掉末尾半个窗口的采样
  if (samples.length > 4) samples.removeLast();
  final avg = samples.isEmpty
      ? 0.0
      : samples.reduce((a, b) => a + b) / samples.length;
  return _TransferResult(
    SpeedPhase(avg: _round2(avg), max: _round2(maxSpeed), samples: samples),
    counter.value,
  );
}

Future<void> _downloadWorker({
  required String host,
  required int port,
  required String path,
  required _ByteCounter counter,
  required _StopFlag stop,
  required List<Socket> sockets,
}) async {
  // 单条连接可能被服务端提前关闭 / 弱网重置：没到时长就重连，
  // 否则并发数会越跑越少，统计口径不变就会低估速率。
  var attempt = 0;
  while (!stop.value) {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
      );
      attempt = 0;
      socket.setOption(SocketOption.tcpNoDelay, true);
      sockets.add(socket);
      socket.write('GET $path HTTP/1.1\r\n'
          'Accept: */*\r\n'
          'Connection: close\r\n'
          'User-Agent: ${Prot.uaDownload}\r\n'
          'Host: ${hostHeader(host)}:$port\r\n\r\n');
      unawaited(socket.flush().catchError((_) {}));
      final done = Completer<void>();
      socket.listen(
        (data) => counter.add(data.length),
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (_) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future;
    } catch (_) {
      attempt++;
      // 连不上时退避一下，别把 CPU 打满
      if (!stop.value && attempt > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: math.min(200 * attempt, 1500)),
        );
      }
    } finally {
      sockets.remove(socket);
      try {
        socket?.destroy();
      } catch (_) {}
    }
    if (!stop.value) {
      // 连接正常结束（服务端关闭或已下满文件）：立刻重连继续压测
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

Future<void> _uploadWorker({
  required String host,
  required int port,
  required String uuid,
  required _ByteCounter counter,
  required _StopFlag stop,
  required List<Socket> sockets,
  required Uint8List block,
  required int seed,
}) async {
  // 上行同理：连接被服务端断开就重连，避免并发数中途缩水
  var attempt = 0;
  while (!stop.value) {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
      );
      attempt = 0;
      socket.setOption(SocketOption.tcpNoDelay, true);
      sockets.add(socket);
      final filename = 'SPEED_${nowSecs()}_${seed % 1000}';
      socket.write('POST ${Prot.uploadPath} HTTP/1.1\r\n'
          'Connection: close\r\n'
          'Cache-Control: no-cache\r\n'
          'Charset: UTF-8\r\n'
          'Key: $uuid\r\n'
          'Content-Type: multipart/form-data;boundary=00content0boundary00\r\n'
          'User-Agent: ${Prot.uaUpload}\r\n'
          'Host: ${hostHeader(host)}:$port\r\n'
          'Accept-Encoding: gzip\r\n'
          'Content-Length: ${Prot.uploadContentLength}\r\n\r\n'
          '--00content0boundary00\r\n'
          'Content-Disposition: form-data; name="upload";filename="$filename"\r\n\r\n');
      var pending = 0;
      var tick = 0;
      while (!stop.value) {
        socket.add(block);
        pending += block.length;
        if (pending >= 256 * 1024) {
          await socket.flush();
          counter.add(pending);
          pending = 0;
          if (++tick % 4 == 0) {
            // 让出事件循环，保证取消指令能被尽快处理
            await Future<void>.delayed(Duration.zero);
          }
        }
      }
      if (pending > 0) {
        await socket
            .flush()
            .timeout(const Duration(milliseconds: 400), onTimeout: () {});
        counter.add(pending);
      }
    } catch (_) {
      // 服务端提前断开：丢弃这轮缓冲，重连继续
      attempt++;
      if (!stop.value) {
        await Future<void>.delayed(
          Duration(milliseconds: math.min(200 * attempt, 1500)),
        );
      }
    } finally {
      sockets.remove(socket);
      try {
        socket?.destroy();
      } catch (_) {}
    }
    if (!stop.value) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

double _round2(double v) => (v * 100).roundToDouble() / 100;
