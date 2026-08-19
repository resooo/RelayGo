import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/free_provider.dart';

/// 免费 API 推荐数据服务（Free LLM API Hub）
///
/// 采用「自动更新 + 本地缓存」策略：
///  - **首次启动**：从远端拉取 providers.json 并缓存到本地；
///  - **缓存策略**：缓存数据 + 时间戳写入 Hive 盒；
///  - **定时更新**：每次 App 启动或进入页面时检查时间戳，超过 24 小时
///    在后台重新请求并刷新缓存；
///  - **离线兜底**：网络请求失败时直接返回本地缓存，不影响浏览。
class FreeApiService {
  final Box<dynamic> _box;
  final http.Client _client;
  final bool _ownsClient;
  final Duration fetchTimeout;

  /// 最近一次刷新结果（供 UI 展示更新时间 / 失败原因）
  FreeApiRefreshResult? lastRefresh;

  FreeApiService({
    Box<dynamic>? box,
    http.Client? httpClient,
    this.fetchTimeout =
        const Duration(seconds: Constants.freeApiFetchTimeoutSeconds),
  })  : _box = box ?? DatabaseHelperFreeApi.box,
        _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// 从本地缓存读取数据集（无网络请求）
  FreeApiDataset? get cached {
    final raw = _box.get(Constants.freeApiCacheKey);
    if (raw is! String || raw.isEmpty) return null;
    try {
      return FreeApiDataset.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  /// 缓存时间戳（毫秒），无缓存返回 null
  int? get cachedAt {
    final v = _box.get(Constants.freeApiCacheTimeKey);
    return v is int ? v : null;
  }

  /// 缓存是否已过期（超过 24 小时）
  bool get isStale {
    final at = cachedAt;
    if (at == null) return true;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age >
        const Duration(hours: Constants.freeApiRefreshHours).inMilliseconds;
  }

  /// 进入页面 / 启动时调用：
  ///  - 缓存为空或过期 → 后台刷新（失败静默，保留旧缓存）
  ///  - 缓存未过期 → 直接返回缓存
  ///
  /// 返回当前可用数据集（可能来自缓存或刚刷新）。
  Future<FreeApiDataset> ensureFresh() async {
    final current = cached;
    if (current != null && !isStale) return current;
    await refresh();
    return cached ?? current ?? const FreeApiDataset(
        version: '', generated: '', source: '');
  }

  /// 强制刷新远端数据并写入缓存。
  ///
  /// 成功返回 true；失败返回 false 并保留旧缓存（离线兜底）。
  Future<bool> refresh() async {
    try {
      final resp = await _client
          .get(Uri.parse(Constants.freeApiFeedUrl), headers: {
            'accept': 'application/json',
            'cache-control': 'no-cache',
          })
          .timeout(fetchTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        lastRefresh = FreeApiRefreshResult(
          ok: false,
          error: 'HTTP ${resp.statusCode}',
          at: DateTime.now().millisecondsSinceEpoch,
        );
        return false;
      }
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) {
        lastRefresh = FreeApiRefreshResult(
          ok: false,
          error: '数据格式异常',
          at: DateTime.now().millisecondsSinceEpoch,
        );
        return false;
      }
      final dataset = FreeApiDataset.fromJson(Map<String, dynamic>.from(decoded));
      if (dataset.providers.isEmpty) {
        lastRefresh = FreeApiRefreshResult(
          ok: false,
          error: '数据为空',
          at: DateTime.now().millisecondsSinceEpoch,
        );
        return false;
      }
      await _box.put(Constants.freeApiCacheKey, jsonEncode(decoded));
      await _box.put(Constants.freeApiCacheTimeKey,
          DateTime.now().millisecondsSinceEpoch);
      lastRefresh = FreeApiRefreshResult(
        ok: true,
        at: DateTime.now().millisecondsSinceEpoch,
      );
      return true;
    } catch (e) {
      lastRefresh = FreeApiRefreshResult(
        ok: false,
        error: e.toString(),
        at: DateTime.now().millisecondsSinceEpoch,
      );
      return false;
    }
  }

  /// 手动清空缓存（测试 / 调试用）
  Future<void> clearCache() async {
    await _box.delete(Constants.freeApiCacheKey);
    await _box.delete(Constants.freeApiCacheTimeKey);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

/// 一次刷新操作的结果
class FreeApiRefreshResult {
  final bool ok;
  final String? error;
  final int at; // 时间戳（毫秒）

  const FreeApiRefreshResult({
    required this.ok,
    this.error,
    required this.at,
  });
}

/// 避免直接依赖 DatabaseHelper 造成循环导入的小工具
class DatabaseHelperFreeApi {
  static Box<dynamic> get box => Hive.box(Constants.freeApiBox);
}
