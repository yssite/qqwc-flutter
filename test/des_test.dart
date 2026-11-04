import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:globalspeed_mobile/core/node.dart';

void main() {
  group('DES / ECB 节点表解密', () {
    test('解密参考向量（OpenSSL/pycryptodome 同一密钥）', () {
      // key = "dw!@#$%^"，plaintext = "hello123"，DES/ECB/no padding
      final cipher = DesCodec.hexDecode('fa7bbb2230938248');
      final plain = DesCodec.decryptBytes(cipher);
      expect(utf8.decode(plain), 'hello123');
    });

    test('加密结果可复现同一密文（PKCS5 补齐后首块一致）', () {
      final encrypted = DesCodec.encryptBytes(Uint8List.fromList(utf8.encode('hello123')));
      expect(DesCodec.hexEncode(encrypted).toUpperCase(),
          startsWith('FA7BBB2230938248'));
    });

    test('解密真实服务端节点表格式（JSON 数组）', () {
      const hex =
          '74DFDB9E3755C8D4DE6EDF4E1FF1755373E2496E3D68FE1D0E5BF2179F58235D'
          'FB134F34DBE6C377D3E1F2B3AD8375BDCAAF0A249DFBDE2D4A7A5F3A42DB9796'
          '47F1D46329BAFBC4BC56364CF19BE518D6A035CBCAA7C84F916112C5B8E57CA15B'
          'BF517003844FDA788572BCCE2A03069ACF503D6355CA485208D2A486EB72DD01C2'
          'A05568502183DAD5E3576A2D0D28AE3E946A54269810C30191BE83AEF7D2';
      final nodes = DesCodec.decryptServerList(hex);
      expect(nodes, hasLength(1));
      expect(nodes.first.hostip, '1.1.1.1');
      expect(nodes.first.hostname, '测试节点');
      expect(nodes.first.oper, '电信');
      expect(nodes.first.portNum, 65499);
    });

    test('非法十六进制抛异常', () {
      expect(() => DesCodec.hexDecode('abc'), throwsA(isA<FormatException>()));
    });
  });
}
