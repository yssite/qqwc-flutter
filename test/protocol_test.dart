import 'package:flutter_test/flutter_test.dart';
import 'package:globalspeed_mobile/core/protocol.dart';
import 'package:globalspeed_mobile/engine/models.dart';
import 'package:globalspeed_mobile/core/node.dart';

void main() {
  group('会话 token', () {
    test('与 Rust/Python 实现逐字节一致', () {
      final token = speedToken(
        model: 'Android',
        imei: 'TS91A8CF8706D645F5',
        time: 1760000000,
        bandwidth: 200,
      );
      expect(token, '5e4028c4872ccc986423a3ce136858ad');
      expect(token.length, 32);
    });

    test('参数变化会改变 token', () {
      final a = speedToken(
          model: 'Android', imei: 'TS1', time: 100, bandwidth: 200);
      final b = speedToken(
          model: 'Android', imei: 'TS1', time: 101, bandwidth: 200);
      expect(a, isNot(b));
    });
  });

  group('URL 构造', () {
    test('percentEncode 编码中文与符号', () {
      expect(percentEncode('北京'), '%E5%8C%97%E4%BA%AC');
      expect(percentEncode('a b'), 'a%20b');
      expect(percentEncode('aZ0-_.~'), 'aZ0-_.~');
    });

    test('IPv6 主机头加方括号', () {
      expect(hostHeader('2408:8000::1'), '[2408:8000::1]');
      expect(hostHeader('1.2.3.4'), '1.2.3.4');
    });

    test('会话路径包含全部必填参数', () {
      final path = sessionPath(
        bandwidth: 200,
        model: 'Android',
        imei: 'TS1',
        time: 1760000000,
        token: 'abc',
      );
      expect(path, contains('flag=true'));
      expect(path, contains('bandwidth=200'));
      expect(path, contains('token=abc'));
      expect(path, contains('pkg=com.cnspeedtest.globalspeed'));
    });
  });

  group('评分', () {
    test('满速低延迟接近满分', () {
      final (score, grade) = scoreOf(1000, 500, 1);
      expect(score, greaterThanOrEqualTo(95));
      expect(grade, '极佳');
    });

    test('无速率高延迟为低分', () {
      final (score, grade) = scoreOf(0, 0, 300);
      expect(score, lessThan(30));
      expect(grade, '较差');
    });

    test('典型千兆宽带打分', () {
      final (score, _) = scoreOf(500, 100, 12);
      expect(score, inInclusiveRange(60, 100));
    });
  });

  group('模型序列化', () {
    test('TestRecord 往返一致', () {
      const record = TestRecord(
        id: '1-abc',
        ts: 1760000000,
        node: Node(
          cityid: '1',
          geoid: '2',
          hostid: '3',
          hostip: '1.2.3.4',
          hostname: '北京联通',
          location: '北京',
          oper: '联通',
          pname: '北京',
          port: '65499',
        ),
        ping: PingStat(avg: 12, min: 10, max: 14, jitter: 1.5, loss: 0),
        down: SpeedPhase(avg: 480.5, max: 512, samples: [480.5, 500]),
        up: SpeedPhase(avg: 42.1, max: 50, samples: [42.1]),
        dnsMs: 8,
        score: 88,
        grade: '优秀',
        uuid: 'u-1',
        net: '192.168.1.5',
      );
      final restored = TestRecord.fromJson(record.toJson());
      expect(restored.id, record.id);
      expect(restored.down.samples, record.down.samples);
      expect(restored.node.hostname, '北京联通');
      expect(restored.score, 88);
    });

    test('节点紧凑格式往返', () {
      const node = Node(
        cityid: '',
        geoid: '',
        hostid: '9',
        hostip: '5.6.7.8',
        hostname: '上海电信',
        location: '上海',
        oper: '电信',
        pname: '上海',
        port: '9443',
      );
      final back = Node.fromCompact(node.toCompact());
      expect(back.hostip, node.hostip);
      expect(back.portNum, 9443);
      expect(back.hostname, node.hostname);
    });
  });
}
