/// 更新状态单例：启动检查、设置页卡片、详情弹层共用同一份状态。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import 'updater.dart';

enum UpdatePhase { idle, checking, latest, found, downloading, ready, error }

class UpdateService extends ChangeNotifier {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// 两次自动检查的最小间隔
  static const Duration autoCheckInterval = Duration(hours: 6);

  UpdateInfo? info;
  UpdateAsset? asset;
  UpdatePhase phase = UpdatePhase.idle;
  String message = '';
  int received = 0;
  int total = 0;
  File? file;
  String currentVersion = '';

  /// 下载优先走镜像（设置里可切换）
  bool preferMirror = false;
  bool _canceled = false;

  DateTime? _lastCheckAt;

  DateTime? get lastCheckAt => _lastCheckAt;

  bool get busy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading;

  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0;

  bool lastCheckOk = false;

  /// [currentVersion] 用于比较；[dueOnly] 为 true 时 6 小时内不重复请求。
  /// 返回 false 表示网络不通，调用方不应把它当成「已检查过」。
  Future<bool> check({
    required String currentVersion,
    bool dueOnly = false,
    DateTime? lastCheck,
  }) async {
    if (busy) return false;
    final last = lastCheck ?? _lastCheckAt;
    if (dueOnly && last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < autoCheckInterval) {
        AppLog.debug('update', '跳过自动检查（${elapsed.inMinutes} 分钟前查过）');
        return true;
      }
    }
    phase = UpdatePhase.checking;
    message = '';
    this.currentVersion = currentVersion;
    notifyListeners();

    final result = await Updater.checkLatest(currentVersion: currentVersion);
    lastCheckOk = result.ok;
    if (!result.ok) {
      info = null;
      asset = null;
      phase = UpdatePhase.latest;
      message = '检查失败：${result.error}';
      notifyListeners();
      return false;
    }
    _lastCheckAt = DateTime.now();
    final found = result.info;
    if (found == null) {
      info = null;
      asset = null;
      phase = UpdatePhase.latest;
      notifyListeners();
      return true;
    }
    final abis = await Updater.abis();
    info = found;
    asset = Updater.pickAsset(found.assets, abis);
    phase = asset == null ? UpdatePhase.error : UpdatePhase.found;
    if (asset == null) message = '这个 Release 里没有可用的安装包';
    notifyListeners();
    return true;
  }

  Future<void> download() async {
    final a = asset;
    if (a == null || phase == UpdatePhase.downloading) return;

    // 已经下好过就不要再下一遍：取消安装后点「更新」应该直接重新拉起安装器
    if (await _reuseDownloaded(a)) {
      phase = UpdatePhase.ready;
      message = '安装包已下载，重新打开安装器';
      notifyListeners();
      await install();
      return;
    }

    phase = UpdatePhase.downloading;
    received = 0;
    total = a.size;
    message = '';
    _canceled = false;
    notifyListeners();
    try {
      final f = await Updater.download(
        a,
        preferMirror: preferMirror,
        onProgress: (r, t) {
          received = r;
          total = t;
          notifyListeners();
        },
        isCanceled: () => _canceled,
      );
      file = f;
      phase = UpdatePhase.ready;
      message = '下载完成，正在唤起安装器';
      notifyListeners();
      await install();
    } on Exception catch (e) {
      phase = isUpdateCanceled(e) ? UpdatePhase.found : UpdatePhase.error;
      message = isUpdateCanceled(e)
          ? '已取消下载'
          : '下载失败（直连与镜像都不可用），可尝试「在浏览器打开」手动下载';
      AppLog.warn('update', '下载失败：$e');
      notifyListeners();
    }
  }

  void setPreferMirror(bool value) {
    if (preferMirror == value) return;
    preferMirror = value;
    AppLog.info('update', '镜像下载${value ? '开启' : '关闭'}');
    notifyListeners();
  }

  void cancelDownload() {
    _canceled = true;
    notifyListeners();
  }

  /// 缓存里已有完整安装包（大小与资源一致）就直接复用。
  Future<bool> _reuseDownloaded(UpdateAsset a) async {
    final cached = file;
    if (cached != null && await _isComplete(cached, a)) {
      AppLog.info('update', '复用已下载的安装包 ${cached.path}');
      return true;
    }
    final guess = await Updater.cachedPath(a);
    if (guess != null && await _isComplete(guess, a)) {
      file = guess;
      AppLog.info('update', '复用缓存安装包 ${guess.path}');
      return true;
    }
    return false;
  }

  Future<bool> _isComplete(File f, UpdateAsset a) async {
    try {
      if (!await f.exists()) return false;
      final len = await f.length();
      return len > 0 && (a.size <= 0 || len == a.size);
    } catch (_) {
      return false;
    }
  }

  /// 卡片 / 弹层的主动作：已下载就安装，否则下载。
  Future<void> primaryAction() async {
    if (phase == UpdatePhase.ready) {
      await install();
      return;
    }
    await download();
  }

  Future<void> install() async {
    final f = file;
    if (f == null) return;
    if (!await Updater.canInstall()) {
      message = '需要允许「安装未知应用」，已跳转到设置';
      await Updater.openInstallSettings();
      notifyListeners();
      return;
    }
    final ok = await Updater.install(f.path);
    phase = UpdatePhase.ready;
    message = ok ? '已打开系统安装器 · 取消后可再次点安装' : '无法唤起安装器，可在发布页手动下载';
    notifyListeners();
  }

  Future<bool> openInstallSettings() => Updater.openInstallSettings();

  Future<bool> openReleasePage() =>
      Updater.openUrl(info?.pageUrl ?? Updater.releasesUrl);
}
