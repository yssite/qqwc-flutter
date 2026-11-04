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
  bool _canceled = false;

  DateTime? _lastCheckAt;

  DateTime? get lastCheckAt => _lastCheckAt;

  bool get busy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading;

  double get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : 0;

  /// [currentVersion] 用于比较；[dueOnly] 为 true 时 6 小时内不重复请求。
  Future<void> check({
    required String currentVersion,
    bool dueOnly = false,
    DateTime? lastCheck,
  }) async {
    if (busy) return;
    final last = lastCheck ?? _lastCheckAt;
    if (dueOnly && last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < autoCheckInterval) {
        AppLog.debug('update', '跳过自动检查（${elapsed.inMinutes} 分钟前查过）');
        return;
      }
    }
    phase = UpdatePhase.checking;
    message = '';
    this.currentVersion = currentVersion;
    notifyListeners();

    final found = await Updater.checkLatest(currentVersion: currentVersion);
    _lastCheckAt = DateTime.now();
    if (found == null) {
      info = null;
      asset = null;
      phase = UpdatePhase.latest;
      notifyListeners();
      return;
    }
    final abis = await Updater.abis();
    info = found;
    asset = Updater.pickAsset(found.assets, abis);
    phase = asset == null ? UpdatePhase.error : UpdatePhase.found;
    if (asset == null) message = '这个 Release 里没有可用的安装包';
    notifyListeners();
  }

  Future<void> download() async {
    final a = asset;
    if (a == null || phase == UpdatePhase.downloading) return;
    phase = UpdatePhase.downloading;
    received = 0;
    total = a.size;
    message = '';
    _canceled = false;
    notifyListeners();
    try {
      final f = await Updater.download(
        a,
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
      message = isUpdateCanceled(e) ? '已取消下载' : '下载失败：$e';
      AppLog.warn('update', '下载失败：$e');
      notifyListeners();
    }
  }

  void cancelDownload() {
    _canceled = true;
    notifyListeners();
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
    message = ok ? '已唤起系统安装器' : '无法唤起安装器，可在发布页手动下载';
    notifyListeners();
  }

  Future<bool> openInstallSettings() => Updater.openInstallSettings();

  Future<bool> openReleasePage() =>
      Updater.openUrl(info?.pageUrl ?? Updater.releasesUrl);
}
