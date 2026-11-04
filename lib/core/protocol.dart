/// CAICT「全球网测」协议常量与签名算法（逆向自 Android v4.4.8）。
///
/// 与桌面版 `app/src-tauri/src/speed.rs` 保持完全一致的口径，便于两端结果互相校验。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class Prot {
  Prot._();

  /// 业务主控（HTTPS）
  static const String base = 'https://dlcv2.cnspeedtest.cn:8443';

  /// 配置 / CDN（节点表、视频规则）
  static const String cdn = 'https://down.cnspeedtest.cn:8043';

  /// 节点表 DES 密钥（libGSCore.so .rodata）
  static const String desKey = r'dw!@#$%^';

  static const String pkgName = 'com.cnspeedtest.globalspeed';
  static const String appName = 'globalspeed';
  static const String tokenSalt = '12345555';

  static const String uaDownload =
      'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/100.0.4896.60 Safari/537.36';
  static const String uaUpload =
      'Dalvik/1.6.0 (Linux; U; Android 4.2.2; GT-I9505 Build/JDQ39)';

  static const String downloadPathTemplate = '/speed/File(1G).dl';
  static const String uploadPath = '/speed/doAnalsLoad.do';
  static const String sessionPath = '/speed/dovalid';

  /// 上行请求里声明的 Content-Length（原版恒为 900000000，实际写到采样结束）
  static const int uploadContentLength = 900000000;
}

int nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

String md5Hex(String input) => md5.convert(utf8.encode(input)).toString();

String randomHex(int length) {
  const alphabet = '0123456789ABCDEF';
  final rnd = _FastRandom(DateTime.now().microsecondsSinceEpoch ^ 0x9E3779B9);
  final sb = StringBuffer();
  for (var i = 0; i < length; i++) {
    sb.write(alphabet[rnd.next() & 0xF]);
  }
  return sb.toString();
}

/// 会话 token：md5( md5("model=..&imei=..") + md5("stime=..&band=..&rand=12345555") )
String speedToken({
  required String model,
  required String imei,
  required int time,
  required int bandwidth,
}) {
  final b1 = 'model=$model&imei=$imei';
  final b2 = 'stime=$time&band=$bandwidth&rand=${Prot.tokenSalt}';
  return md5Hex('${md5Hex(b1)}${md5Hex(b2)}');
}

String percentEncode(String input) {
  final sb = StringBuffer();
  for (final byte in utf8.encode(input)) {
    final ok = (byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        byte == 0x2D ||
        byte == 0x5F ||
        byte == 0x2E ||
        byte == 0x7E;
    if (ok) {
      sb.writeCharCode(byte);
    } else {
      sb.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return sb.toString();
}

/// IPv6 字面量在 Host 头里要加方括号
String hostHeader(String host) => host.contains(':') ? '[$host]' : host;

String downloadPath(String uuid) =>
    '${Prot.downloadPathTemplate}?r=${nowSecs()}&key=$uuid';

String sessionPath({
  required int bandwidth,
  required String model,
  required String imei,
  required int time,
  required String token,
}) {
  return '${Prot.sessionPath}?key=&flag=true'
      '&bandwidth=$bandwidth'
      '&model=${percentEncode(model)}'
      '&imei=${percentEncode(imei)}'
      '&time=$time'
      '&app=${Prot.appName}'
      '&token=$token'
      '&pkg=${Prot.pkgName}';
}

/// 轻量 HTTP 客户端：只用 dart:io，不引三方库，isolate 内可直接用。
class HttpText {
  HttpText._();

  static Future<String> get(String url,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 4)
      ..autoUncompress = true;
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
      req.headers.set(HttpHeaders.userAgentHeader,
          'GlobalSpeedTest/1.0 (Android) Flutter');
      final resp = await req.close().timeout(timeout);
      final body = await resp.transform(utf8.decoder).join().timeout(timeout);
      if (resp.statusCode >= 400) {
        throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> getJson(String url,
      {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final text = await get(url, timeout: timeout);
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }
}

/// 简单 xorshift，测速上行随机数据用（比 Random.secure 快一个数量级）。
class _FastRandom {
  _FastRandom(int seed) : _state = (seed == 0 ? 0x9E3779B97F4A7C15 : seed) | 1;
  int _state;

  int next() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFFFFFFFFFF;
    x ^= x >> 7;
    x ^= (x << 17) & 0xFFFFFFFFFFFFFFFF;
    _state = x;
    return x;
  }
}

void fillRandomBytes(List<int> buffer, int seed) {
  final rnd = _FastRandom(seed);
  var i = 0;
  while (i < buffer.length) {
    var v = rnd.next();
    for (var k = 0; k < 8 && i < buffer.length; k++) {
      buffer[i++] = v & 0xFF;
      v >>= 8;
    }
  }
}
