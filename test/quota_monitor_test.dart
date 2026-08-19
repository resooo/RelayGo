import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/alert.dart';
import 'package:relaygo/models/user_settings.dart';
import 'package:relaygo/services/quota_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

ApiKey _key({int dailyQuota = 1000, String dayStamp = '', String monthStamp = ''}) =>
    ApiKey(
      id: 'k1',
      provider: 'openai',
      encryptedKey: 'enc',
      name: 'k1',
      dailyQuota: dailyQuota,
      dayStamp: dayStamp,
      monthStamp: monthStamp,
      createdAt: 0,
    );

void main() {
  group('滚动重置', () {
    test('跨日重置用量计数', () {
      final k = _key(dayStamp: '20200101');
      final m = QuotaMonitor(settings: UserSettings());
      final now = DateTime(2020, 1, 2);
      final alerts = m.recordUsage(k, tokens: 10, at: now);
      expect(k.usedToday, 10);
      expect(k.requestsToday, 1);
      // 日戳已更新
      expect(k.dayStamp, '20200102');
      expect(alerts, isEmpty);
    });

    test('跨日产生日报并恢复 exhausted', () {
      final k = _key(dayStamp: '20200101')
        ..status = KeyStatus.exhausted
        ..requestsToday = 10
        ..usedToday = 5
        ..errorsToday = 1;
      final m = QuotaMonitor(settings: UserSettings());
      final alerts = m.recordUsage(k, tokens: 10, at: DateTime(2020, 1, 2));
      expect(k.status, KeyStatus.active);
      expect(alerts.any((a) => a.event == 'report.daily'), isTrue);
    });
  });

  group('额度告警', () {
    test('达到预警阈值触发 quota.warning', () {
      final k = _key(dailyQuota: 100);
      final m = QuotaMonitor(settings: UserSettings(quotaWarnThreshold: 0.9));
      final alerts = m.recordUsage(k, tokens: 95);
      expect(alerts.any((a) => a.event == 'quota.warning'), isTrue);
    });

    test('达到 100% 触发 exhausted 且不再重复告警', () {
      final k = _key(dailyQuota: 100);
      final m = QuotaMonitor(settings: UserSettings());
      final first = m.recordUsage(k, tokens: 100);
      expect(k.status, KeyStatus.exhausted);
      expect(first.any((a) => a.event == 'quota.exhausted'), isTrue);
      // 再次记录不应重复 exhausted 告警
      final second = m.recordUsage(k, tokens: 0);
      expect(second.any((a) => a.event == 'quota.exhausted'), isFalse);
    });
  });

  group('错误率告警', () {
    test('错误率超过阈值且样本充足时告警', () {
      final k = _key();
      final m = QuotaMonitor(settings: UserSettings(errorRateThreshold: 0.5));
      final alerts = <Alert>[];
      // 12 次请求，其中 8 次错误
      for (var i = 0; i < 12; i++) {
        alerts.addAll(m.recordUsage(k, error: i < 8));
      }
      expect(alerts.any((a) => a.event == 'error_rate.high'), isTrue);
    });
  });

  group('token 计费', () {
    test('成功计入 token，失败仅计请求数', () {
      final k = _key(dailyQuota: 10000);
      final m = QuotaMonitor(settings: UserSettings());
      m.recordUsage(k, tokens: 50, error: false);
      expect(k.usedToday, 50);
      m.recordUsage(k, tokens: 50, error: true);
      expect(k.usedToday, 50); // 失败不累加 token
      expect(k.requestsToday, 2);
      expect(k.errorsToday, 1);
    });
  });
}
