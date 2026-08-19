import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:relaygo/config/constants.dart';

/// 一条缓存的上游响应
class CachedResponse {
  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
  final int storedAt; // 写入时间（毫秒）
  final int expireAt; // 过期时间（毫秒）
  final String provider;
  final String model;

  const CachedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.storedAt,
    required this.expireAt,
    this.provider = '',
    this.model = '',
  });

  bool isExpired([int? nowMs]) =>
      expireAt <= (nowMs ?? DateTime.now().millisecondsSinceEpoch);

  int get ageSeconds =>
      ((DateTime.now().millisecondsSinceEpoch - storedAt) / 1000).round();

  int get sizeBytes => body.length;
}

/// 缓存统计
class CacheStats {
  final int hits;
  final int misses;
  final int stores;
  final int evictions;
  final int expirations;
  final int entries;
  final int bytes;

  const CacheStats({
    this.hits = 0,
    this.misses = 0,
    this.stores = 0,
    this.evictions = 0,
    this.expirations = 0,
    this.entries = 0,
    this.bytes = 0,
  });

  int get lookups => hits + misses;

  double get hitRate => lookups == 0 ? 0 : hits / lookups;

  Map<String, dynamic> toJson() => {
        'hits': hits,
        'misses': misses,
        'stores': stores,
        'evictions': evictions,
        'expirations': expirations,
        'entries': entries,
        'bytes': bytes,
        'lookups': lookups,
        'hit_rate': hitRate,
      };
}

/// 响应缓存（需求 2.2.4）
///
/// - **键**：`method + path + query + provider + 请求体` 的 SHA-256，
///   保证相同语义请求命中同一条目，且不同 provider/模型互不串味；
/// - **TTL**：可配置（默认 5 分钟），读取时惰性淘汰过期项；
/// - **容量**：LRU（`LinkedHashMap` 重插入刷新热度），超限淘汰最冷；
/// - **命中率统计**：hits / misses / stores / evictions；
/// - **只缓存可安全复用的响应**：2xx、非流式、体积不超过上限；
/// - **GET/POST 区分**：method 参与哈希，天然区分。
class CacheManager {
  /// 生存时间
  Duration ttl;

  /// 条目上限
  int maxEntries;

  /// 单条响应体上限（超过不缓存，避免内存膨胀）
  int maxBodyBytes;

  /// 总开关
  bool enabled;

  final LinkedHashMap<String, CachedResponse> _store = LinkedHashMap();

  int _hits = 0;
  int _misses = 0;
  int _stores = 0;
  int _evictions = 0;
  int _expirations = 0;

  CacheManager({
    this.ttl = const Duration(seconds: Constants.defaultCacheTtlSeconds),
    this.maxEntries = Constants.defaultCacheMaxEntries,
    this.maxBodyBytes = Constants.cacheMaxBodyBytes,
    this.enabled = false,
  });

  /// 生成缓存键（对外暴露以便日志/测试复用）
  static String buildKey({
    required String method,
    required String path,
    String query = '',
    String provider = '',
    List<int> body = const [],
  }) {
    final head = utf8.encode('${method.toUpperCase()} $path?$query|$provider|');
    final digest = sha256.convert(<int>[...head, ...body]);
    return digest.toString();
  }

  /// 该请求是否可缓存（写入前判定）
  ///
  /// 只缓存幂等可复用的正常响应：2xx、非流式、体积不超限。
  bool isCacheable({
    required String method,
    required int statusCode,
    required bool streaming,
    required int bodyBytes,
  }) {
    if (!enabled) return false;
    if (streaming) return false; // SSE 流式响应内容与时序相关，不缓存
    if (statusCode < 200 || statusCode >= 300) return false;
    if (bodyBytes > maxBodyBytes) return false;
    final m = method.toUpperCase();
    if (m != 'GET' && m != 'POST') return false;
    return true;
  }

  /// 读取缓存。未命中或已过期返回 null。
  CachedResponse? get(String key) {
    if (!enabled) return null;
    final e = _store[key];
    if (e == null) {
      _misses++;
      return null;
    }
    if (e.isExpired()) {
      _store.remove(key);
      _expirations++;
      _misses++;
      return null;
    }
    // 刷新 LRU 热度
    _store.remove(key);
    _store[key] = e;
    _hits++;
    return e;
  }

  /// 写入缓存
  void put(
    String key, {
    required int statusCode,
    required Map<String, String> headers,
    required List<int> body,
    String provider = '',
    String model = '',
    Duration? ttlOverride,
  }) {
    if (!enabled) return;
    if (body.length > maxBodyBytes) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final life = ttlOverride ?? ttl;
    _store.remove(key);
    _store[key] = CachedResponse(
      statusCode: statusCode,
      headers: Map<String, String>.from(headers),
      body: List<int>.from(body),
      storedAt: now,
      expireAt: now + life.inMilliseconds,
      provider: provider,
      model: model,
    );
    _stores++;
    _evictOverflow();
  }

  void _evictOverflow() {
    while (maxEntries > 0 && _store.length > maxEntries) {
      _store.remove(_store.keys.first); // LinkedHashMap 首个即最冷
      _evictions++;
    }
  }

  /// 主动清理已过期项，返回清理条数
  int purgeExpired() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dead = <String>[];
    _store.forEach((k, v) {
      if (v.isExpired(now)) dead.add(k);
    });
    for (final k in dead) {
      _store.remove(k);
    }
    _expirations += dead.length;
    return dead.length;
  }

  /// 手动清除全部缓存（保留累计统计）
  void clear() => _store.clear();

  /// 清除缓存并重置统计
  void reset() {
    _store.clear();
    _hits = 0;
    _misses = 0;
    _stores = 0;
    _evictions = 0;
    _expirations = 0;
  }

  int get size => _store.length;

  int get bytes {
    var n = 0;
    for (final e in _store.values) {
      n += e.sizeBytes;
    }
    return n;
  }

  double get hitRate => stats.hitRate;

  CacheStats get stats => CacheStats(
        hits: _hits,
        misses: _misses,
        stores: _stores,
        evictions: _evictions,
        expirations: _expirations,
        entries: _store.length,
        bytes: bytes,
      );
}
