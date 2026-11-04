import 'package:flutter_test/flutter_test.dart';
import 'package:globalspeed_mobile/data/link_service.dart';
import 'package:globalspeed_mobile/data/province_geo.dart';

void main() {
  group('蜂窝链路文案', () {
    test('4G 有频段与频宽时全部展示', () {
      final link = LinkInfo.fromMap({
        'type': 'cellular',
        'cell': {
          'networkType': 13,
          'nr': false,
          'lteBand': 'B3',
          'lteBandwidthMhz': 20,
          'rsrp': -95,
        },
      });
      expect(link.tag, '4G B3');
      expect(link.detail, '4G B3 20MHz -95 RSRP');
      expect(link.kindKey, 'cell');
    });

    test('5G 拿不到频宽时隐去 MHz 段', () {
      final link = LinkInfo.fromMap({
        'type': 'cellular',
        'cell': {
          'networkType': 20,
          'nr': true,
          'nrBand': 'n41',
          'nrBandwidthMhz': 0,
          'rsrp': -78,
        },
      });
      expect(link.tag, '5G n41');
      expect(link.detail, '5G n41 -78 RSRP');
      expect(link.detail.contains('MHz'), isFalse);
    });

    test('5G 若能读到频宽则照常展示', () {
      final link = LinkInfo.fromMap({
        'type': 'cellular',
        'cell': {
          'networkType': 20,
          'nr': true,
          'nrBand': 'n78',
          'nrBandwidthMhz': 100,
          'rsrp': -85,
        },
      });
      expect(link.detail, '5G n78 100MHz -85 RSRP');
    });

    test('NSA 5G：网络制式为 LTE 但标记了 nr', () {
      final link = LinkInfo.fromMap({
        'type': 'cellular',
        'cell': {'networkType': 13, 'nr': true, 'nrBand': 'n1'},
      });
      expect(link.tag, '5G n1');
    });
  });

  group('WiFi 链路文案', () {
    test('WiFi6 5GHz 160MHz', () {
      final link = LinkInfo.fromMap({
        'type': 'wifi',
        'wifi': {
          'freqMhz': 5180,
          'rssi': -60,
          'standard': 'WiFi6',
          'bandwidthMhz': 160,
        },
      });
      expect(link.tag, '5G WiFi6');
      expect(link.detail, 'WiFi6 5GHz 160MHz -60 RSSI');
      expect(link.kindKey, 'wifi');
    });

    test('2.4G WiFi4 且拿不到频宽', () {
      final link = LinkInfo.fromMap({
        'type': 'wifi',
        'wifi': {'freqMhz': 2437, 'rssi': -52, 'standard': 'WiFi4'},
      });
      expect(link.tag, '2.4G WiFi4');
      expect(link.detail, 'WiFi4 2.4GHz -52 RSSI');
    });

    test('无制式信息时退回频段 + WiFi', () {
      final link = LinkInfo.fromMap({
        'type': 'wifi',
        'wifi': {'freqMhz': 5745, 'rssi': -70},
      });
      expect(link.tag, '5G WiFi');
    });
  });

  group('其它链路', () {
    test('有线网络', () {
      final link = LinkInfo.fromMap({'type': 'ethernet'});
      expect(link.tag, '有线网络');
      expect(link.detail, '有线网络');
      expect(link.kindKey, 'lan');
    });

    test('VPN 叠加标注', () {
      final link = LinkInfo.fromMap({
        'type': 'cellular',
        'vpn': true,
        'cell': {'networkType': 13, 'lteBand': 'B1'},
      });
      expect(link.vpn, isTrue);
      expect(link.tag, '4G B1');
    });

    test('未连接时为空', () {
      final link = LinkInfo.fromMap({'type': 'none'});
      expect(link.tag, '');
      expect(link.isEmpty, isTrue);
      expect(link.kindKey, '');
    });
  });

  group('权限与版本', () {
    test('权限映射缺省为未授权', () {
      final perms = LinkPermissions.fromMap(null);
      expect(perms.location, isFalse);
      expect(perms.phone, isFalse);
      expect(perms.any, isFalse);
    });

    test('版本号展示格式', () {
      expect(const AppVersion(name: '1.2.1', code: 12100).display,
          'v1.2.1 (12100)');
      expect(const AppVersion().display, 'v--');
      expect(const AppVersion().isEmpty, isTrue);
    });
  });

  group('定位省份兜底', () {
    test('Geocoder 返回全称时规范成简称', () {
      // 走 provinceOf 的离线边界：广州 ≈ 广东
      expect(provinceOf(23.1291, 113.2644), '广东');
      expect(provinceOf(39.9042, 116.4074), '北京');
      expect(provinceOf(31.2304, 121.4737), '上海');
      expect(provinceOf(0, 0), '');
    });
  });
}
