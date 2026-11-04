/// 运行日志：内存环形缓冲 + 详细模式落盘，设置页可一键导出。
///
/// 设计目标：出问题时用户只需要「设置 → 诊断日志 → 导出」，就能拿到足够复盘的上下文
/// （链路快照、双卡诊断、权限、测速各阶段、异常栈）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLog {
  AppLog._();

  static const int _capacity = 3000;
  static final List<String> _lines = <String>[];
  static final List<String> _pending = <String>[];

  static bool _verbose = false;
  static File? _file;
  static Timer? _flushTimer;

  static bool get verbose => _verbose;

  static int get lineCount => _lines.length;

  /// 启动时调用一次；[verbose] 来自设置项。
  static Future<void> init({bool verbose = false}) async {
    _verbose = verbose;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      final file = File('${logDir.path}/app.log');
      if (await file.exists() && await file.length() > 512 * 1024) {
        await file.writeAsString('');
      }
      _file = file;
    } catch (_) {
      // 拿不到目录就只保留内存日志
    }
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 3), (_) => _flush());
    _add('I', 'log', '日志就绪（详细模式 ${_verbose ? '开' : '关'}）');
  }

  static void setVerbose(bool value) {
    if (_verbose == value) return;
    _verbose = value;
    _add('I', 'log', '详细日志${value ? '开启' : '关闭'}');
  }

  static void info(String tag, String msg) => _add('I', tag, msg);

  static void warn(String tag, String msg) => _add('W', tag, msg);

  static void error(String tag, String msg, [Object? error, StackTrace? st]) {
    _add('E', tag, error == null ? msg : '$msg | $error');
    if (st != null) {
      _add('E', tag, st.toString().split('\n').take(6).join(' ⏎ '));
    }
  }

  /// 只在详细模式下记录，避免正常使用时刷屏。
  static void debug(String tag, String msg) {
    if (!_verbose) return;
    _add('D', tag, msg);
  }

  static void _add(String level, String tag, String msg) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final line = '$ts $level/$tag $msg';
    _lines.add(line);
    if (_lines.length > _capacity) {
      _lines.removeRange(0, _lines.length - _capacity);
    }
    if (_verbose) {
      _pending.add(line);
      if (_pending.length >= 20) _flush();
    }
    if (kDebugMode) debugPrint(line);
  }

  static void _flush() {
    final file = _file;
    if (file == null || _pending.isEmpty) return;
    final text = _pending.join('\n');
    _pending.clear();
    try {
      file.writeAsStringSync('$text\n', mode: FileMode.append, flush: false);
    } catch (_) {
      // 落盘失败不影响主流程
    }
  }

  static String get tail => _lines.join('\n');

  /// 导出为临时文件，交给系统分享面板。
  static Future<File> export({String? header}) async {
    _flush();
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final file = File('${dir.path}/flutterwangce-log-$stamp.txt');

    final sb = StringBuffer()
      ..writeln('# Flutter 网测 运行日志')
      ..writeln('# 导出时间：${now.toIso8601String()}');
    if (header != null && header.isNotEmpty) {
      for (final line in header.split('\n')) {
        sb.writeln('# $line');
      }
    }
    sb
      ..writeln()
      ..writeln('=== 本次会话（${_lines.length} 行） ===')
      ..writeln(_lines.isEmpty ? '（空）' : tail);

    final persisted = _file;
    if (persisted != null && await persisted.exists()) {
      final text = await persisted.readAsString();
      if (text.trim().isNotEmpty) {
        sb
          ..writeln()
          ..writeln('=== 持久化日志（详细模式） ===')
          ..write(text);
      }
    }

    await file.writeAsString(sb.toString(), flush: true);
    return file;
  }

  static Future<void> clear() async {
    _lines.clear();
    _pending.clear();
    try {
      await _file?.writeAsString('');
    } catch (_) {}
  }
}
