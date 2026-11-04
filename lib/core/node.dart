/// 节点模型 + 节点表（DES/ECB/PKCS5 加密的 JSON 数组）解密。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/block/modes/ecb.dart';

import 'protocol.dart';

class Node {
  const Node({
    required this.cityid,
    required this.geoid,
    required this.hostid,
    required this.hostip,
    required this.hostname,
    required this.location,
    required this.oper,
    required this.pname,
    required this.port,
  });

  final String cityid;
  final String geoid;
  final String hostid;
  final String hostip;
  final String hostname;
  final String location;
  final String oper;
  final String pname;
  final String port;

  int get portNum => int.tryParse(port) ?? 65499;

  /// 运营商字段缺失时，从节点名（如「成都电信」）反推
  String get operLabel =>
      oper.isNotEmpty ? oper : guessOper(hostname);

  static String guessOper(String name) {
    if (name.contains('电信')) return '电信';
    if (name.contains('联通')) return '联通';
    if (name.contains('移动')) return '移动';
    if (name.contains('教育')) return '教育网';
    if (name.contains('广电')) return '广电网';
    return '';
  }

  String get key => '$hostip:$port';

  factory Node.fromJson(Map<String, dynamic> json) => Node(
        cityid: '${json['cityid'] ?? ''}',
        geoid: '${json['geoid'] ?? ''}',
        hostid: '${json['hostid'] ?? ''}',
        hostip: '${json['hostip'] ?? ''}',
        hostname: '${json['hostname'] ?? ''}',
        location: '${json['location'] ?? ''}',
        oper: '${json['oper'] ?? ''}',
        pname: '${json['pname'] ?? ''}',
        port: '${json['port'] ?? '65499'}',
      );

  Map<String, dynamic> toJson() => {
        'cityid': cityid,
        'geoid': geoid,
        'hostid': hostid,
        'hostip': hostip,
        'hostname': hostname,
        'location': location,
        'oper': oper,
        'pname': pname,
        'port': port,
      };

  /// isolate 之间传递用的紧凑形式（省掉 3 个客户端用不到的字段）
  List<String> toCompact() => [hostip, port, hostname, pname, oper, hostid];

  static Node fromCompact(List<dynamic> v) => Node(
        cityid: '',
        geoid: '',
        hostid: v.length > 5 ? '${v[5]}' : '',
        hostip: v.isNotEmpty ? '${v[0]}' : '',
        hostname: v.length > 2 ? '${v[2]}' : '',
        // 紧凑格式里没有 location 字段，留空交给 pname 兜底
        location: '',
        oper: v.length > 4 ? '${v[4]}' : '',
        pname: v.length > 3 ? '${v[3]}' : '',
        port: v.length > 1 ? '${v[1]}' : '65499',
      );

  @override
  bool operator ==(Object other) => other is Node && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// 节点表加解密：DES/ECB/PKCS5Padding，密钥 `dw!@#$%^`，密文为整段大写十六进制文本。
///
/// pointycastle 4 只保留 3DES 引擎；把同一把 8 字节密钥重复三次喂进去，
/// EDE 退化为单 DES，与 Java 侧 `DesUtil` 的 DES/ECB 结果逐字节一致。
class DesCodec {
  DesCodec._();

  static Uint8List _key() {
    final k = Uint8List.fromList(utf8.encode(Prot.desKey));
    return Uint8List.fromList([...k, ...k, ...k]);
  }

  static ECBBlockCipher _cipher(bool encrypt) {
    final cipher = ECBBlockCipher(DESedeEngine());
    cipher.init(encrypt, KeyParameter(_key()));
    return cipher;
  }

  static Uint8List decryptBytes(Uint8List data) {
    final cipher = _cipher(false);
    final out = Uint8List(data.length);
    for (var i = 0; i + 8 <= data.length; i += 8) {
      cipher.processBlock(data, i, out, i);
    }
    // PKCS5 去填充
    if (out.isNotEmpty) {
      final pad = out.last;
      if (pad > 0 && pad <= 8 && pad <= out.length) {
        return Uint8List.sublistView(out, 0, out.length - pad);
      }
    }
    return out;
  }

  static Uint8List encryptBytes(Uint8List data) {
    final pad = 8 - (data.length % 8);
    final buf = Uint8List(data.length + pad)..setAll(0, data);
    buf.fillRange(data.length, buf.length, pad);
    final cipher = _cipher(true);
    final out = Uint8List(buf.length);
    for (var i = 0; i + 8 <= buf.length; i += 8) {
      cipher.processBlock(buf, i, out, i);
    }
    return out;
  }

  static Uint8List hexDecode(String hex) {
    final text = hex.trim();
    if (text.length.isOdd) throw const FormatException('十六进制长度必须为偶数');
    final out = Uint8List(text.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(text.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String hexEncode(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();

  static List<Node> decryptServerList(String hexText) {
    final bytes = decryptBytes(hexDecode(hexText));
    final text = utf8.decode(bytes);
    final list = jsonDecode(text) as List<dynamic>;
    return list
        .map((e) => Node.fromJson(e as Map<String, dynamic>))
        .where((n) => n.hostip.isNotEmpty)
        .toList(growable: false);
  }
}

/// 节点库：内置 596 条兜底，联网后可增量刷新。
class NodeRepository {
  NodeRepository._();

  static List<Node>? _cache;

  static Future<List<Node>> bundled() async {
    final cached = _cache;
    if (cached != null) return cached;
    final text = await rootBundle.loadString('assets/nodes.json');
    final list = jsonDecode(text) as List<dynamic>;
    final nodes = list
        .map((e) => Node.fromJson(e as Map<String, dynamic>))
        .where((n) => n.hostip.isNotEmpty)
        .toList(growable: false);
    _cache = nodes;
    return nodes;
  }

  /// 拉取远端最新节点表（配置清单 → serverlist_encrypt_url → DES 解密）。
  static Future<List<Node>> fetchLatest() async {
    final manifestUrl = '${Prot.base}/TaierAndroid/Config/ConfigMD5.php'
        '?province=${percentEncode('北京')}&city=${percentEncode('北京')}'
        '&imei=TS0000000000000000&appname=${percentEncode('全球网测')}'
        '&vercode=40408&type=globalspeed&ipv6=0';
    final text = await HttpText.get(manifestUrl,
        timeout: const Duration(seconds: 12));
    final items = jsonDecode(text) as List<dynamic>;
    String? url;
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      if (map['name'] == 'serverlist_encrypt_url') {
        final filename = '${map['filename']}';
        url = filename.startsWith('http')
            ? filename
            : '${Prot.cdn}/TaierAndroid/Config/$filename';
        break;
      }
    }
    if (url == null) throw Exception('配置清单中没有节点表');
    final hex = await HttpText.get(url, timeout: const Duration(seconds: 25));
    final nodes = DesCodec.decryptServerList(hex);
    if (nodes.length < 10) throw Exception('节点表数量异常');
    _cache = nodes;
    return nodes;
  }

  static List<String> provinces(List<Node> nodes) {
    final set = <String>{};
    for (final n in nodes) {
      if (n.pname.isNotEmpty) set.add(n.pname);
    }
    final list = set.toList()..sort();
    return list;
  }

  static List<String> cities(List<Node> nodes, String province) {
    final set = <String>{};
    for (final n in nodes) {
      if (n.pname == province && n.location.isNotEmpty) set.add(n.location);
    }
    final list = set.toList()..sort();
    return list;
  }

  static const List<String> operList = ['电信', '移动', '联通', '教育网', '广电网'];

  /// 就近兜底：按省份 + 运营商过滤，逐级放宽。
  static List<Node> localCandidates(
    List<Node> nodes, {
    required String province,
    required String oper,
  }) {
    // 用 operLabel（缺失时从节点名反推），避免 oper 字段为空的节点被运营商过滤掉
    bool matchesOper(Node n) => oper.isEmpty || n.operLabel == oper ||
        n.operLabel.contains(oper);

    var list = nodes
        .where((n) => n.pname == province && matchesOper(n))
        .toList();
    if (list.isEmpty) {
      list = nodes.where((n) => n.pname == province).toList();
    }
    if (list.isEmpty) {
      list = nodes.where(matchesOper).toList();
    }
    if (list.isEmpty) list = nodes.toList();
    return list;
  }
}
