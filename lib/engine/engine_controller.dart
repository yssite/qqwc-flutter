/// 主线程侧的引擎句柄：拉起 isolate、把事件流映射成强类型对象、负责取消与回收。
library;

import 'dart:async';
import 'dart:isolate';

import '../core/node.dart';
import 'engine_isolate.dart';
import 'models.dart';

class EngineHandle {
  EngineHandle._(this._isolate, this._port, this.events);

  final Isolate _isolate;
  final ReceivePort _port;
  final Stream<EngineEvent> events;

  SendPort? _command;
  bool _disposed = false;
  bool _cancelRequested = false;

  void _bind(SendPort command) {
    _command = command;
    if (_cancelRequested) command.send({'cmd': 'cancel'});
  }

  void cancel() {
    if (_disposed) return;
    _cancelRequested = true;
    _command?.send({'cmd': 'cancel'});
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _port.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class SpeedEngine {
  SpeedEngine._();

  /// 拉起一个引擎 isolate 并立即开始测速。事件流在 done/failed/canceled 后自动关闭。
  static Future<EngineHandle> start(EngineRequest request) async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(engineIsolateMain, receive.sendPort);
    final controller = StreamController<EngineEvent>.broadcast();
    late final EngineHandle handle;

    late final StreamSubscription<dynamic> sub;
    sub = receive.listen((raw) {
      final map = (raw as Map).cast<String, dynamic>();
      if (map['t'] == 'port') {
        handle._bind(map['port'] as SendPort);
        handle._command!.send({'cmd': 'start', 'req': request.toMap()});
        return;
      }
      final event = decodeEvent(map);
      if (event == null) return;
      controller.add(event);
      if (event is EngineDone ||
          event is EngineFailure ||
          event is EngineCanceled) {
        unawaited(sub.cancel());
        receive.close();
        isolate.kill(priority: Isolate.immediate);
        unawaited(controller.close());
      }
    });

    handle = EngineHandle._(isolate, receive, controller.stream);
    return handle;
  }
}

EngineEvent? decodeEvent(Map<String, dynamic> map) {
  switch (map['t']) {
    case 'phase':
      final phase = _phaseOf('${map['phase']}');
      if (phase == null) return null;
      return EnginePhase(phase, note: map['note'] as String?);
    case 'node':
      return EngineNode(
        Node.fromCompact(map['node'] as List<dynamic>),
        candidates: (map['count'] as num?)?.toInt() ?? 0,
      );
    case 'ping':
      return EnginePing(
        PingStat.fromJson((map['ping'] as Map).cast<String, dynamic>()),
        (map['dns'] as num?)?.toDouble() ?? 0,
      );
    case 'sample':
      return EngineSample(
        upload: '${map['dir']}' == 'up',
        sample: Sample(
          idx: (map['i'] as num?)?.toInt() ?? 0,
          speed: (map['speed'] as num?)?.toDouble() ?? 0,
          bytes: (map['bytes'] as num?)?.toInt() ?? 0,
          preheat: map['p'] == true,
          elapsedMs: (map['e'] as num?)?.toInt() ?? 0,
        ),
      );
    case 'phaseResult':
      final avg = (map['avg'] as num?)?.toDouble() ?? 0;
      final max = (map['max'] as num?)?.toDouble() ?? 0;
      final samples = (map['samples'] as List<dynamic>? ?? const [])
          .map((e) => (e as num).toDouble())
          .toList(growable: false);
      return EnginePhaseResult(
        upload: '${map['dir']}' == 'up',
        phase: SpeedPhase(avg: avg, max: max, samples: samples),
        bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      );
    case 'done':
      return EngineDone(
        TestRecord.fromJson((map['record'] as Map).cast<String, dynamic>()),
      );
    case 'error':
      return EngineFailure('${map['message']}');
    case 'canceled':
      return const EngineCanceled();
    default:
      return null;
  }
}

TestPhase? _phaseOf(String value) {
  for (final phase in TestPhase.values) {
    if (phase.name == value) return phase;
  }
  return null;
}
