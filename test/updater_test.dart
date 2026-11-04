import 'package:flutter_test/flutter_test.dart';
import 'package:globalspeed_mobile/data/updater.dart';

UpdateAsset _a(String name, {int size = 1000}) =>
    UpdateAsset(name: name, url: 'https://example.com/$name', size: size);

void main() {
  group('版本比较', () {
    test('补丁位递增算新版', () {
      expect(Updater.isNewer('1.2.10', '1.2.9'), isTrue);
      expect(Updater.isNewer('1.2.9', '1.2.10'), isFalse);
    });

    test('位数不同也能正确比较', () {
      expect(Updater.isNewer('1.3', '1.2.9'), isTrue);
      expect(Updater.isNewer('1.2.9.1', '1.2.9'), isTrue);
      expect(Updater.isNewer('1.2.9', '1.2.9'), isFalse);
    });

    test('tag 里的前缀与后缀不影响判断', () {
      expect(Updater.isNewer('v1.3.0', '1.2.5'), isTrue);
      expect(Updater.isNewer('1.2.5-beta', '1.2.5'), isFalse);
    });
  });

  group('安装包选择', () {
    final assets = [
      _a('FlutterWangCe_1.3.0_universal.apk', size: 55),
      _a('FlutterWangCe_1.3.0_arm64-v8a.apk', size: 20),
      _a('FlutterWangCe_1.3.0_armeabi-v7a.apk', size: 18),
    ];

    test('优先匹配设备 ABI', () {
      expect(Updater.pickAsset(assets, ['arm64-v8a', 'armeabi-v7a'])?.name,
          contains('arm64-v8a'));
      expect(Updater.pickAsset(assets, ['armeabi-v7a', 'arm64-v8a'])?.name,
          contains('armeabi-v7a'));
    });

    test('没有匹配 ABI 时回退 universal', () {
      expect(Updater.pickAsset(assets, ['x86_64'])?.name, contains('universal'));
    });

    test('都匹配不到就取第一个，空列表返回 null', () {
      expect(Updater.pickAsset([_a('app-debug.apk')], ['arm64-v8a'])?.name,
          'app-debug.apk');
      expect(Updater.pickAsset(const [], const ['arm64-v8a']), isNull);
    });
  });

  group('下载取消', () {
    test('取消异常能识别', () {
      expect(isUpdateCanceled(Exception('x')), isFalse);
      expect(isUpdateCanceled(StateError('x')), isFalse);
    });
  });
}
