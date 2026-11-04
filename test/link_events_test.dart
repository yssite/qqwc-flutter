import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globalspeed_mobile/data/link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('globalspeed/netlink');
  const codec = StandardMethodCodec();

  /// 模拟原生 → Dart 的推送
  Future<void> pushNative(String method, Object? args) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  test('原生链路变化会转成 changes 流', () async {
    LinkService.init();
    final first = LinkService.changes.first;
    await pushNative('linkChanged', 'capabilities');
    expect(await first, 'capabilities');
  });

  test('多次推送都能收到，且顺序不乱', () async {
    LinkService.init();
    final events = <String>[];
    final sub = LinkService.changes.listen(events.add);
    await pushNative('linkChanged', 'available');
    await pushNative('linkChanged', 'display');
    await pushNative('linkChanged', 'lost');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events, ['available', 'display', 'lost']);
  });

  test('其它方法名不会污染链路流', () async {
    LinkService.init();
    var fired = 0;
    final sub = LinkService.changes.listen((_) => fired++);
    await pushNative('somethingElse', null);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(fired, 0);
  });
}
