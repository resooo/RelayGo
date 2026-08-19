import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/config/constants.dart';

/// 存储结构迁移
///
/// Hive 以 Map 存储，字段增删本身向后兼容；此处负责「语义层」升级：
/// 补齐 Phase 2 新增字段的默认值，避免旧数据读取后再写回时丢字段。
class Migrations {
  /// 当前数据结构版本
  static const int currentVersion = 3;
  static const String versionKey = 'schema_version';

  static Future<void> run() async {
    final settings = Hive.box(Constants.settingsBox);
    final from = settings.get(versionKey) as int? ?? 1;
    if (from >= currentVersion) return;

    if (from < 2) {
      await _v1ToV2();
    }
    if (from < 3) {
      await _v2ToV3();
    }

    await settings.put(versionKey, currentVersion);
  }

  /// v1 -> v2：key 补齐分组与用量统计字段；日志补齐 model/token 字段
  static Future<void> _v1ToV2() async {
    final keys = Hive.box(Constants.keysBox);
    for (final k in keys.keys.toList()) {
      final raw = keys.get(k);
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      m.putIfAbsent('group', () => '');
      m.putIfAbsent('used_month', () => 0);
      m.putIfAbsent('requests_today', () => 0);
      m.putIfAbsent('requests_month', () => 0);
      m.putIfAbsent('errors_today', () => 0);
      m.putIfAbsent('day_stamp', () => '');
      m.putIfAbsent('month_stamp', () => '');
      await keys.put(k, m);
    }

    final logs = Hive.box(Constants.logsBox);
    for (final k in logs.keys.toList()) {
      final raw = logs.get(k);
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      m.putIfAbsent('key_id', () => '');
      m.putIfAbsent('key_name', () => '');
      m.putIfAbsent('model', () => '');
      m.putIfAbsent('request_bytes', () => 0);
      m.putIfAbsent('response_bytes', () => 0);
      m.putIfAbsent('streaming', () => false);
      m.putIfAbsent('retries', () => 0);
      await logs.put(k, m);
    }
  }

  /// v2 -> v3：日志补齐缓存/限流标记；用户设置补齐 Phase 3 字段
  static Future<void> _v2ToV3() async {
    final logs = Hive.box(Constants.logsBox);
    for (final k in logs.keys.toList()) {
      final raw = logs.get(k);
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      m.putIfAbsent('cached', () => false);
      m.putIfAbsent('rate_limited', () => '');
      await logs.put(k, m);
    }

    final settings = Hive.box(Constants.settingsBox);
    final raw = settings.get('user');
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      m.putIfAbsent('cache_enabled', () => false);
      m.putIfAbsent('cache_ttl_seconds', () => Constants.defaultCacheTtlSeconds);
      m.putIfAbsent(
          'cache_max_entries', () => Constants.defaultCacheMaxEntries);
      m.putIfAbsent('ip_rate_limit_per_minute',
          () => Constants.defaultIpRateLimitPerMinute);
      m.putIfAbsent('global_rpm_limit', () => Constants.defaultGlobalRpmLimit);
      m.putIfAbsent('token_rate_limit_per_minute',
          () => Constants.defaultTokenRateLimitPerMinute);
      m.putIfAbsent('burst_multiplier', () => Constants.defaultBurstMultiplier);
      m.putIfAbsent('update_feed_url', () => Constants.defaultUpdateFeedUrl);
      m.putIfAbsent('update_channel', () => Constants.defaultUpdateChannel);
      m.putIfAbsent('auto_check_update', () => true);
      await settings.put('user', m);
    }
  }
}
