import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:globalspeed_mobile/data/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SIM 运营商口径', () {
    test('广电按移动处理（借用移动基站与核心网）', () {
      expect(NetInfoService.simOperOf('中国广电'), '移动');
      expect(NetInfoService.simOperOf('中国广电 5G'), '移动');
    });

    test('三大运营商与英文名', () {
      expect(NetInfoService.simOperOf('中国电信'), '电信');
      expect(NetInfoService.simOperOf('China Unicom'), '联通');
      expect(NetInfoService.simOperOf('中国移动'), '移动');
      expect(NetInfoService.simOperOf('CHN-UNICOM'), '联通');
      expect(NetInfoService.simOperOf('T-Mobile'), '移动');
    });

    test('未知名称返回空', () {
      expect(NetInfoService.simOperOf(''), '');
      expect(NetInfoService.simOperOf('Vodafone UK'), '');
    });

    test('出口 IP 的广电仍归为广电网，不被 SIM 口径污染', () {
      expect(NetInfoService.operOf('中国广电'), '广电网');
    });
  });

  group('设置迁移', () {
    test('旧数据（无 schema）会把自动写入的运营商清掉', () async {
      SharedPreferences.setMockInitialValues({
        'app_settings_v1': jsonEncode({
          'oper': '电信',
          'province': '四川',
          'deviceId': 'TS0000000000000000',
        }),
      });
      final settings = await SettingsStore.load();
      expect(settings.oper, '');
      expect(settings.province, '四川', reason: '省份是用户可选项，不该被清');
      expect(settings.schema, 3);
    });

    test('已经迁移过的设置不会被再次清空', () async {
      SharedPreferences.setMockInitialValues({
        'app_settings_v1': jsonEncode({
          'oper': '联通',
          'schema': 3,
          'deviceId': 'TS0000000000000000',
        }),
      });
      final settings = await SettingsStore.load();
      expect(settings.oper, '联通');
    });

    test('schema 往返保持一致', () {
      final s = AppSettings(oper: '移动');
      final back = AppSettings.fromJson(
        (jsonDecode(jsonEncode(s.toJson())) as Map).cast<String, dynamic>(),
      );
      expect(back.oper, '移动');
      expect(back.schema, 3);
    });
  });
}
