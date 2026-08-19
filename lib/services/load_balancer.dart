import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/api_key.dart';

/// 负载均衡器
///
/// 支持策略（需求 2.1.3）：
///  - round_robin：轮询
///  - weighted_round_robin：加权轮询
///  - priority：优先级优先
///  - least_connections：最少连接
///  - response_time：响应最快优先
///  - smart：按错误率/优先级综合切换
///
/// 失败切换规则：
///  - 连续失败 [Constants.maxFailureThreshold] 次标记为 error 并进入 [Constants.cooldownSeconds] 冷却
///  - 冷却结束后自动恢复为 active
class LoadBalancer {
  int _rrIndex = 0;
  final Map<String, int> _connections = {}; // keyId -> 活跃连接数
  final Map<String, int> _latency = {}; // keyId -> 累计耗时（ms）

  // —— P1：smart 健康分（滑动窗口成功率 + 延迟 EMA）——
  final int _successWindow = 50; // 成功率滑动窗口大小
  final int _minSamplesForHealth = 10; // 启用健康分所需的最少样本
  final double _latencyEmaAlpha = 0.2; // 延迟指数移动平均平滑因子
  final Map<String, List<bool>> _recent = {}; // keyId -> 近 N 次成功/失败
  final Map<String, double> _latencyEma = {}; // keyId -> 延迟 EMA（ms）
  final Map<String, int> _latencyEmaCount = {}; // keyId -> EMA 已更新的样本数

  /// 样本是否足以启用健康分：候选 ≥ 2 且每个候选都积累了足够样本。
  bool _enoughSamples(List<ApiKey> keys) {
    if (keys.length < 2) return false;
    for (final k in keys) {
      if ((_recent[k.id]?.length ?? 0) < _minSamplesForHealth) return false;
    }
    return true;
  }

  /// 单 Key 健康分：successRate * 0.6 + latencyScore * 0.4。
  /// 样本不足时返回 null（由调用方回退到优先级排序）。
  double? _healthScore(ApiKey k) {
    final win = _recent[k.id];
    if (win == null || win.length < _minSamplesForHealth || win.isEmpty) {
      return null;
    }
    final success = win.where((b) => b).length;
    final successRate = success / win.length;
    final ema = _latencyEma[k.id];
    final latScore = (ema == null || (_latencyEmaCount[k.id] ?? 0) == 0)
        ? 0.5 // 无延迟样本取中性
        : _latencyScore(ema);
    return successRate * 0.6 + latScore * 0.4;
  }

  /// 延迟(ms) → 0..1 得分
  double _latencyScore(num ms) {
    if (ms < 300) return 1.0;
    if (ms < 500) return 0.9;
    if (ms < 800) return 0.7;
    if (ms < 1200) return 0.5;
    if (ms < 2000) return 0.3;
    return 0.1;
  }

  /// smart 排序：样本充足时按健康分降序；否则回退到「优先级高 → 失败少」。
  int _smartCompare(ApiKey a, ApiKey b, bool useHealth) {
    if (useHealth) {
      final ha = _healthScore(a);
      final hb = _healthScore(b);
      if (ha != null && hb != null && ha != hb) {
        return hb.compareTo(ha);
      }
    }
    if (a.priority != b.priority) {
      return b.priority.compareTo(a.priority);
    }
    return a.failureCount.compareTo(b.failureCount);
  }

  /// 从候选 key 中按策略选一个可用 key
  ApiKey? pick(List<ApiKey> keys, String strategy) {
    final active = keys.where(_isAvailable).toList();
    if (active.isEmpty) return null;

    switch (strategy) {
      case 'priority':
        active.sort((a, b) => b.priority.compareTo(a.priority));
        return active.first;
      case 'weighted_round_robin':
        return _weightedRoundRobin(active);
      case 'least_connections':
        active.sort((a, b) => (_connections[a.id] ?? 0)
            .compareTo(_connections[b.id] ?? 0));
        return active.first;
      case 'response_time':
        active.sort((a, b) => (_latency[a.id] ?? 0)
            .compareTo(_latency[b.id] ?? 0));
        return active.first;
      case 'smart':
        final useHealth = _enoughSamples(active);
        active.sort((a, b) => _smartCompare(a, b, useHealth));
        return active.first;
      case 'round_robin':
      default:
        return _roundRobin(active);
    }
  }

  bool _isAvailable(ApiKey k) {
    if (k.status != KeyStatus.active) return false;
    if (k.cooldownUntil != null &&
        k.cooldownUntil! > DateTime.now().millisecondsSinceEpoch) {
      return false;
    }
    return true;
  }

  /// 按策略对候选 key 排序（不消费状态），供代理服务器构建「多 key 候选池」时使用。
  /// round_robin 会按内部游标轮转，使并发请求分散到不同 key。
  List<ApiKey> rank(List<ApiKey> keys, String strategy) {
    final active = keys.where(_isAvailable).toList();
    switch (strategy) {
      case 'priority':
        active.sort((a, b) => b.priority.compareTo(a.priority));
        return active;
      case 'weighted_round_robin':
        active.sort((a, b) => b.weight.compareTo(a.weight));
        return active;
      case 'least_connections':
        active.sort((a, b) =>
            (_connections[a.id] ?? 0).compareTo(_connections[b.id] ?? 0));
        return active;
      case 'response_time':
        active.sort((a, b) =>
            (_latency[a.id] ?? 0).compareTo(_latency[b.id] ?? 0));
        return active;
      case 'smart':
        final useHealth = _enoughSamples(active);
        active.sort((a, b) => _smartCompare(a, b, useHealth));
        return active;
      case 'round_robin':
      default:
        if (active.isEmpty) return active;
        final rotated = <ApiKey>[];
        for (var i = 0; i < active.length; i++) {
          rotated.add(active[(_rrIndex + i) % active.length]);
        }
        _rrIndex++;
        return rotated;
    }
  }

  ApiKey _roundRobin(List<ApiKey> keys) {
    final k = keys[_rrIndex % keys.length];
    _rrIndex++;
    return k;
  }

  ApiKey _weightedRoundRobin(List<ApiKey> keys) {
    final total = keys.fold<int>(0, (sum, k) => sum + (k.weight <= 0 ? 1 : k.weight));
    var r = _rrIndex % (total == 0 ? 1 : total);
    _rrIndex++;
    for (final k in keys) {
      final w = k.weight <= 0 ? 1 : k.weight;
      if (r < w) return k;
      r -= w;
    }
    return keys.first;
  }

  /// 记录成功：清零失败计数、更新延迟
  void recordSuccess(ApiKey key, {int latencyMs = 0}) {
    key.failureCount = 0;
    key.lastUsed = DateTime.now().millisecondsSinceEpoch;
    _latency[key.id] = (_latency[key.id] ?? 0) + latencyMs;
    // P1：喂入成功率窗口 + 延迟 EMA
    _feed(key.id, true, latencyMs);
    if (key.status != KeyStatus.active) {
      key.status = KeyStatus.active;
      key.cooldownUntil = null;
    }
  }

  /// 记录失败：达到阈值则标记 error 并冷却
  void recordFailure(ApiKey key) {
    key.failureCount++;
    // P1：喂入成功率窗口（失败不更新延迟）
    _feed(key.id, false, null);
    if (key.failureCount >= Constants.maxFailureThreshold) {
      key.status = KeyStatus.error;
      key.cooldownUntil =
          DateTime.now().millisecondsSinceEpoch + Constants.cooldownSeconds * 1000;
    }
  }

  /// 维护 P1 健康分指标：滑动窗口成功率 + 延迟 EMA。
  void _feed(String keyId, bool success, int? latencyMs) {
    final win = _recent.putIfAbsent(keyId, () => <bool>[])
      ..add(success);
    if (win.length > _successWindow) {
      win.removeAt(0);
    }
    if (success && latencyMs != null && latencyMs >= 0) {
      final ema = _latencyEma[keyId];
      final count = _latencyEmaCount[keyId] ?? 0;
      _latencyEma[keyId] = count == 0
          ? latencyMs.toDouble()
          : ema! + _latencyEmaAlpha * (latencyMs - ema);
      _latencyEmaCount[keyId] = count + 1;
    }
  }

  void incConnection(String id) =>
      _connections[id] = (_connections[id] ?? 0) + 1;

  void decConnection(String id) {
    _connections[id] = (_connections[id] ?? 1) - 1;
    if ((_connections[id] ?? 0) < 0) _connections[id] = 0;
  }

  void reset() {
    _rrIndex = 0;
    _connections.clear();
    _latency.clear();
    _recent.clear();
    _latencyEma.clear();
    _latencyEmaCount.clear();
  }
}
