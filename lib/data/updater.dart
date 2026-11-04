/// 应用内更新：查询 GitHub Release、多线程分段下载 APK、交给系统安装器。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_log.dart';

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final int size;

  double get sizeMb => size / (1024 * 1024);
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.assets,
  });

  final String version;
  final String notes;
  final String pageUrl;
  final List<UpdateAsset> assets;
}

class Updater {
  Updater._();

  static const String repo = 'yssite/qqwc-flutter';
  static const String repoUrl = 'https://github.com/$repo';
  static const String releasesUrl = '$repoUrl/releases';
  static const String _apiLatest =
      'https://api.github.com/repos/$repo/releases/latest';

  static const _channel = MethodChannel('globalspeed/updater');

  /// 当前设备 ABI（如 arm64-v8a），取不到返回空。
  static Future<List<String>> abis() async {
    try {
      final list = await _channel.invokeListMethod<String>('abis');
      return list ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> canInstall() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('info');
      return map?['installAllowed'] == true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openInstallSettings() async {
    try {
      return await _channel.invokeMethod<bool>('installSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> install(String path) async {
    try {
      return await _channel.invokeMethod<bool>('install', {'path': path}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 查询最新 Release。返回 null 表示已是最新或查询失败（error 里有原因）。
  static Future<UpdateInfo?> checkLatest({
    required String currentVersion,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(_apiLatest));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'FlutterWangCe');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        AppLog.warn('update', 'GitHub API ${res.statusCode}');
        return null;
      }
      final text = await res.transform(utf8.decoder).join();
      final map = jsonDecode(text) as Map<String, dynamic>;
      final tag = '${map['tag_name'] ?? ''}';
      final version = tag.replaceFirst(RegExp(r'^v'), '');
      if (version.isEmpty) return null;
      final assets = <UpdateAsset>[];
      for (final item in (map['assets'] as List<dynamic>? ?? const [])) {
        final a = (item as Map).cast<String, dynamic>();
        assets.add(
          UpdateAsset(
            name: '${a['name'] ?? ''}',
            url: '${a['browser_download_url'] ?? ''}',
            size: (a['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      final info = UpdateInfo(
        version: version,
        notes: '${map['body'] ?? ''}',
        pageUrl: '${map['html_url'] ?? releasesUrl}',
        assets: assets,
      );
      AppLog.info('update', '最新版本 $version，资源 ${assets.length} 个');
      if (!isNewer(version, currentVersion)) return null;
      return info;
    } catch (e) {
      AppLog.warn('update', '检查更新失败：$e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 语义化版本比较：`1.2.10 > 1.2.9`。
  static bool isNewer(String candidate, String current) {
    final a = _parse(candidate);
    final b = _parse(current);
    for (var i = 0; i < math.max(a.length, b.length); i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parse(String v) {
    final cleaned = v.trim().replaceFirst(RegExp(r'^[vV]'), '');
    return cleaned
        .split(RegExp(r'[.+-]'))
        .map((part) {
          final m = RegExp(r'\d+').firstMatch(part);
          return m == null ? 0 : int.parse(m.group(0)!);
        })
        .toList(growable: false);
  }

  /// 按设备 ABI 选择安装包，找不到就用 universal。
  static UpdateAsset? pickAsset(List<UpdateAsset> assets, List<String> abis) {
    for (final abi in abis) {
      final hit = assets.where((a) => a.name.contains(abi)).toList();
      if (hit.isNotEmpty) return hit.first;
    }
    final universal = assets
        .where((a) => a.name.contains('universal'))
        .toList();
    if (universal.isNotEmpty) return universal.first;
    return assets.isEmpty ? null : assets.first;
  }

  /// 多线程分段下载（GitHub 直连慢，分段并发能明显提速）。
  static Future<File> download(
    UpdateAsset asset, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCanceled,
    int threads = 6,
  }) async {
    final dir = await getTemporaryDirectory();
    final target = File('${dir.path}/update-${asset.name}');
    if (await target.exists()) await target.delete();

    final total = await _probeSize(asset.url, fallback: asset.size);
    final usable = total > 1024 * 1024;
    final count = usable ? math.min(threads, 8) : 1;

    final parts = <File>[];
    final received = List<int>.filled(count, 0);

    Future<void> fetchRange(int index, int start, int end) async {
      final part = File('${target.path}.part$index');
      parts.add(part);
      final sink = part.openWrite();
      var got = 0;
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.getUrl(Uri.parse(asset.url));
        req.headers.set(HttpHeaders.userAgentHeader, 'FlutterWangCe');
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        final res = await req.close();
        if (res.statusCode != 200 && res.statusCode != 206) {
          throw HttpException('HTTP ${res.statusCode}');
        }
        await for (final chunk in res) {
          if (isCanceled?.call() == true) break;
          sink.add(chunk);
          got += chunk.length;
          received[index] = got;
          onProgress?.call(received.fold(0, (a, b) => a + b), total);
        }
      } finally {
        await sink.close();
        client.close(force: true);
      }
    }

    if (isCanceled?.call() == true) throw const _Canceled();

    if (count == 1) {
      await fetchRange(0, 0, math.max(0, total - 1));
    } else {
      final chunk = (total / count).ceil();
      final futures = <Future<void>>[];
      for (var i = 0; i < count; i++) {
        final start = i * chunk;
        final end = math.min(total - 1, start + chunk - 1);
        if (start > end) break;
        futures.add(fetchRange(i, start, end));
      }
      await Future.wait(futures);
    }

    if (isCanceled?.call() == true) throw const _Canceled();

    // 合并分段
    final sink = target.openWrite();
    try {
      parts.sort((a, b) => a.path.compareTo(b.path));
      for (final part in parts) {
        if (await part.exists()) {
          await sink.addStream(part.openRead());
          await part.delete();
        }
      }
    } finally {
      await sink.close();
    }

    final length = await target.length();
    AppLog.info('update', '下载完成 ${asset.name} $length/$total 字节');
    if (total > 0 && length != total) {
      await target.delete();
      throw FileSystemException('下载不完整（$length/$total）');
    }
    onProgress?.call(length, total);
    return target;
  }

  /// 用 0-0 的 Range 请求拿总长度，顺便判断是否支持分段。
  static Future<int> _probeSize(String url, {int fallback = 0}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'FlutterWangCe');
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final res = await req.close();
      final range = res.headers.value(HttpHeaders.contentRangeHeader);
      await res.drain<void>();
      if (range != null && range.contains('/')) {
        final total = int.tryParse(range.split('/').last.trim()) ?? 0;
        if (total > 0) return total;
      }
      final len = res.contentLength;
      if (len > 0) return len;
    } catch (e) {
      AppLog.warn('update', '探测大小失败：$e');
    } finally {
      client.close(force: true);
    }
    return fallback;
  }

  static Future<void> clearDownloads() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('update-')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }
}

class _Canceled implements Exception {
  const _Canceled();
}

bool isUpdateCanceled(Object error) => error is _Canceled;
