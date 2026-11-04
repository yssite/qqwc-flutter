import 'package:flutter_test/flutter_test.dart';
import 'package:globalspeed_mobile/core/app_log.dart';

void main() {
  group('运行日志', () {
    setUp(() async {
      await AppLog.clear();
    });

    test('info 会进入环形缓冲，带级别与标签', () {
      AppLog.info('link', 'cell sub=1');
      final text = AppLog.tail;
      expect(text, contains('I/link'));
      expect(text, contains('cell sub=1'));
      expect(AppLog.lineCount, greaterThan(0));
    });

    test('详细模式关闭时 debug 不记录，开启后记录', () {
      AppLog.setVerbose(false);
      final before = AppLog.lineCount;
      AppLog.debug('test', '被丢弃的明细');
      expect(AppLog.lineCount, before);

      AppLog.setVerbose(true);
      AppLog.debug('test', '采样 100Mbps');
      expect(AppLog.tail, contains('采样 100Mbps'));
      AppLog.setVerbose(false);
    });

    test('error 会带上异常信息与栈的首行', () {
      AppLog.error('test', '连接失败', StateError('boom'), StackTrace.current);
      final text = AppLog.tail;
      expect(text, contains('E/test'));
      expect(text, contains('boom'));
    });

    test('清空后缓冲为空', () async {
      AppLog.info('x', 'y');
      await AppLog.clear();
      expect(AppLog.lineCount, 0);
      expect(AppLog.tail, isEmpty);
    });

    test('环形缓冲不超过上限', () {
      for (var i = 0; i < 3100; i++) {
        AppLog.info('flood', 'line $i');
      }
      expect(AppLog.lineCount, lessThanOrEqualTo(3000));
      expect(AppLog.tail, contains('line 3099'));
      expect(AppLog.tail, isNot(contains('line 0\n')));
    });
  });
}
