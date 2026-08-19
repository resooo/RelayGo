import 'package:relaygo/models/alert.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/user_settings.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 告警回调（应用层据此持久化并触发 Webhook）
typedef AlertEmitter = void Function(Alert alert);

/// 额度监控（需求 2.2.2）
///
/// 职责：
///  - 按日 / 按月滚动重置用量与计数；
///  - 记录每次请求的 token 消耗、请求数、错误数；
///  - 在额度接近阈值、额度耗尽、错误率过高时产生告警；
///  - 额度耗尽后将 key 标记为 exhausted（自动退出轮询，次日自动恢复）。
///
/// 设计为「纯逻辑」：直接修改传入的 [ApiKey] 并返回产生的告警，
/// 由调用方（AppState / ProxyServer）负责持久化 key 与派发告警。
class QuotaMonitor {
  final UserSettings settings;
  final AlertEmitter? onAlert;

  /// 已告警状态（避免重复打扰；key 日滚动时清理）
  final Map<String, Set<String>> _warned = {};

  QuotaMonitor({required this.settings, this.onAlert});

  /// 月滚动发生的处理：清零上月用量
  void _rolloverMonth(ApiKey key, String month) {
    key.usedMonth = 0;
    key.requestsMonth = 0;
    key.monthStamp = month;
  }

  /// 日滚动发生的处理：清零当日用量，并（按需）生成日报、恢复 exhausted 状态
  List<Alert> _rolloverDay(ApiKey key, String day, DateTime now) {
    final alerts = <Alert>[];
    final prevRequests = key.requestsToday;
    final prevTokens = key.usedToday;
    final prevErrors = key.errorsToday;

    key.usedToday = 0;
    key.requestsToday = 0;
    key.errorsToday = 0;
    key.dayStamp = day;
    _warned.remove(key.id); // 新的一天允许重新告警

    // 额度耗尽在跨日后自动恢复（实现「exhausted → 自动切换」的次日恢复）
    if (key.status == KeyStatus.exhausted) {
      key.status = KeyStatus.active;
      key.cooldownUntil = null;
      alerts.add(_statusChanged(key, '额度已重置，恢复可用'));
    }

    // 日报（仅在有用量时产生）
    if (prevRequests > 0) {
      alerts.add(Alert(
        id: _alertId('report.daily', key.id, now),
        timestamp: now.millisecondsSinceEpoch,
        event: AlertEvent.dailyReport,
        level: AlertLevel.info,
        title: L10n.fmt('每日用量报告 · {name}', {'name': key.name}),
        message: L10n.fmt('昨日请求 {n} 次，消耗 {t} token，错误 {e} 次',
            {'n': '$prevRequests', 't': '$prevTokens', 'e': '$prevErrors'}),
        keyId: key.id,
        data: {
          'requests': prevRequests,
          'tokens': prevTokens,
          'errors': prevErrors,
          'name': key.name,
        },
      ));
    }
    return alerts;
  }

  /// 若日 / 月已变更则滚动重置（不记录新用量）。返回由此产生的告警。
  List<Alert> rollIfNeeded(ApiKey key, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final alerts = <Alert>[];
    final day = _dayStamp(now);
    final month = _monthStamp(now);
    if (key.monthStamp != month) _rolloverMonth(key, month);
    if (key.dayStamp != day) alerts.addAll(_rolloverDay(key, day, now));
    return alerts;
  }

  /// 请求结束后调用：累加计数与 token，并检测告警。返回产生的告警。
  List<Alert> recordUsage(ApiKey key,
      {int tokens = 0, bool error = false, DateTime? at}) {
    final now = at ?? DateTime.now();
    final alerts = rollIfNeeded(key, at: now);

    key.requestsToday++;
    key.requestsMonth++;
    // 失败请求仅计入请求数与错误数，不累加 token 用量（避免为未成功完成的请求计费）
    if (!error) {
      key.usedToday += tokens;
      key.usedMonth += tokens;
    }
    if (error) key.errorsToday++;

    // —— 额度告警 ——
    if (key.dailyQuota > 0) {
      final ratio = key.usedToday / key.dailyQuota;
      if (ratio >= 1 && key.status != KeyStatus.exhausted) {
        key.status = KeyStatus.exhausted;
        alerts.add(Alert(
          id: _alertId(AlertEvent.quotaExhausted, key.id, now),
          timestamp: now.millisecondsSinceEpoch,
          event: AlertEvent.quotaExhausted,
          level: AlertLevel.critical,
          title: L10n.fmt('额度耗尽 · {name}', {'name': key.name}),
          message: L10n.fmt('今日额度 {q} token 已用尽（{used}），该 key 已退出轮询。',
              {'q': '${key.dailyQuota}', 'used': '${key.usedToday}'}),
          keyId: key.id,
          data: {'used': key.usedToday, 'quota': key.dailyQuota},
        ));
        alerts.add(_statusChanged(key, '额度耗尽'));
      } else if (ratio >= settings.quotaWarnThreshold) {
        final flag = '${key.id}:quota';
        if (!_isWarned(flag)) {
          _markWarned(flag);
          alerts.add(Alert(
            id: _alertId(AlertEvent.quotaWarning, key.id, now),
            timestamp: now.millisecondsSinceEpoch,
            event: AlertEvent.quotaWarning,
            level: AlertLevel.warning,
            title: L10n.fmt('额度预警 · {name}', {'name': key.name}),
            message: L10n.fmt('今日额度已使用 {pct}%（{used}/{quota}）', {
              'pct': (ratio * 100).toStringAsFixed(1),
              'used': '${key.usedToday}',
              'quota': '${key.dailyQuota}',
            }),
            keyId: key.id,
            data: {'ratio': ratio, 'used': key.usedToday, 'quota': key.dailyQuota},
          ));
        }
      }
    }

    // —— 错误率告警（需一定样本量，避免偶发误报）——
    if (key.requestsToday >= 10 && key.errorRate >= settings.errorRateThreshold) {
      final flag = '${key.id}:error';
      if (!_isWarned(flag)) {
        _markWarned(flag);
        alerts.add(Alert(
          id: _alertId(AlertEvent.errorRateHigh, key.id, now),
          timestamp: now.millisecondsSinceEpoch,
          event: AlertEvent.errorRateHigh,
          level: AlertLevel.warning,
          title: L10n.fmt('错误率偏高 · {name}', {'name': key.name}),
          message: L10n.fmt('今日错误率 {pct}%（{err}/{req}）', {
            'pct': (key.errorRate * 100).toStringAsFixed(1),
            'err': '${key.errorsToday}',
            'req': '${key.requestsToday}',
          }),
          keyId: key.id,
          data: {'rate': key.errorRate, 'errors': key.errorsToday},
        ));
      }
    }

    for (final a in alerts) {
      onAlert?.call(a);
    }
    return alerts;
  }

  Alert _statusChanged(ApiKey key, String reason) => Alert(
        id: _alertId(AlertEvent.keyStatusChanged, key.id, DateTime.now()),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        event: AlertEvent.keyStatusChanged,
        level: AlertLevel.info,
        title: 'Key 状态变化 · $key.name',
        message: '$key.status.label（$reason）',
        keyId: key.id,
        data: {'status': key.status.name, 'reason': reason},
      );

  bool _isWarned(String flag) => _warned[keyPrefix(flag)]?.contains(flag) ?? false;

  void _markWarned(String flag) {
    final keyId = keyPrefix(flag);
    _warned.putIfAbsent(keyId, () => <String>{}).add(flag);
  }

  String keyPrefix(String flag) => flag.split(':').first;

  static String _dayStamp(DateTime d) =>
      '${d.year}${_pad(d.month)}${_pad(d.day)}';

  static String _monthStamp(DateTime d) => '${d.year}${_pad(d.month)}';

  static String _pad(int v) => v.toString().padLeft(2, '0');

  static String _alertId(String event, String keyId, DateTime now) =>
      '$event-$keyId-${now.millisecondsSinceEpoch}';
}
