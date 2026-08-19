import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/api_key.dart';

/// 限流判定结果
class RateLimitResult {
  final bool allowed;

  /// 触发的限流维度：key_rpm / key_tpm / ip / global / concurrency
  final String dimension;

  /// 建议客户端等待的秒数（用于 Retry-After 响应头）
  final int retryAfterSeconds;

  final String message;

  const RateLimitResult.allow()
      : allowed = true,
        dimension = '',
        retryAfterSeconds = 0,
        message = '';

  const RateLimitResult.deny(
    this.dimension, {
    this.retryAfterSeconds = 1,
    this.message = '',
  }) : allowed = false;
}

/// 令牌桶：平滑限流 + 允许突发
///
/// 容量 = 速率 × 突发倍数，空闲时累积令牌以吸收瞬时峰值。
class TokenBucket {
  double tokens;
  final double capacity;
  final double refillPerSec;
  double _last;

  TokenBucket({required this.capacity, required this.refillPerSec, double? nowSec})
      : tokens = capacity,
        _last = nowSec ?? DateTime.now().millisecondsSinceEpoch / 1000;

  /// 尝试取 [cost] 个令牌
  bool tryConsume({double cost = 1, double? nowSec}) {
    _refill(nowSec);
    if (tokens >= cost) {
      tokens -= cost;
      return true;
    }
    return false;
  }

  /// 兼容旧接口
  bool allow() => tryConsume();

  /// 距离可取 [cost] 个令牌还需等待的秒数
  int waitSecondsFor(double cost) {
    if (refillPerSec <= 0) return 60;
    final missing = cost - tokens;
    if (missing <= 0) return 0;
    return (missing / refillPerSec).ceil();
  }

  void _refill([double? nowSec]) {
    final now = nowSec ?? DateTime.now().millisecondsSinceEpoch / 1000;
    final dt = now - _last;
    if (dt <= 0) return;
    tokens = (tokens + dt * refillPerSec).clamp(0, capacity).toDouble();
    _last = now;
  }
}

/// 滑动窗口计数器：精确统计「最近 N 秒内」的事件数/权重
class SlidingWindow {
  final int windowMs;
  final List<List<int>> _events = []; // [时间戳, 权重]

  SlidingWindow(Duration window) : windowMs = window.inMilliseconds;

  void record(int weight, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _events.add(<int>[now, weight]);
    _trim(now);
  }

  int sum({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _trim(now);
    var total = 0;
    for (final e in _events) {
      total += e[1];
    }
    return total;
  }

  int count({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _trim(now);
    return _events.length;
  }

  /// 最旧事件滑出窗口所需的秒数（用于 Retry-After）
  int retryAfterSeconds({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _trim(now);
    if (_events.isEmpty) return 0;
    final oldest = _events.first[0];
    final ms = windowMs - (now - oldest);
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  void _trim(int now) {
    _events.removeWhere((e) => now - e[0] > windowMs);
  }

  void clear() => _events.clear();
}

/// 高级限流器（需求 2.2.6）
///
/// 维度：
///  1. **每个 key 的请求速率**（RPM，令牌桶 + 突发）；
///  2. **每个 key 的 token 消耗速率**（TPM，滑动窗口，响应后记账）；
///  3. **单个 IP 请求速率**（滑动窗口，入口拦截）；
///  4. **全局请求速率**（滑动窗口，保护整机）；
///  5. **并发连接数**（由代理服务器的信号量承担，这里只提供计数辅助）。
///
/// 超限统一返回 429 + `Retry-After`。
class RateLimiter {
  /// 每个 key 的 RPM 由 ApiKey.maxRequestsPerMinute 决定，这里只配突发倍数
  double burstMultiplier;

  /// 每个 key 每分钟 token 上限（0 = 不限制）
  int tokensPerMinutePerKey;

  /// 是否启用「自适应 TPM 挡板」。
  ///
  /// 默认开启。开启后，除了用 [tokensPerMinutePerKey]（若配置了）做硬拦，
  /// 还会结合上游 429 反馈，学习每个 key+模型的实际 token 上限（AIMD），
  /// 发请求前先按「学到的上限 × 余量系数」挡板，从源头减少 TPM 429。
  bool adaptiveTpmEnabled;

  /// 单 IP 每分钟请求上限（0 = 不限制）
  int requestsPerMinutePerIp;

  /// 全局每分钟请求上限（0 = 不限制）
  int globalRequestsPerMinute;

  bool enabled;

  final Map<String, TokenBucket> _keyBuckets = {};
  final Map<String, SlidingWindow> _keyTokenWindows = {};
  final Map<String, SlidingWindow> _ipWindows = {};
  final SlidingWindow _globalWindow = SlidingWindow(const Duration(minutes: 1));

  /// 各维度的拒绝计数（供统计报表展示）
  final Map<String, int> denials = {};

  // —— 自适应 TPM 状态（AIMD 学习到的每 key+模型实际上限）——
  /// keyId + '|' + model → 学到的 TPM 上限（token/分钟）。
  final Map<String, int> _learnedTpm = {};
  /// keyId + '|' + model → 上次无 429 的稳定时长累计（ms），用于加性增。
  final Map<String, int> _tpmStableMs = {};

  RateLimiter({
    this.burstMultiplier = Constants.defaultBurstMultiplier,
    this.tokensPerMinutePerKey = Constants.defaultTokenRateLimitPerMinute,
    this.requestsPerMinutePerIp = Constants.defaultIpRateLimitPerMinute,
    this.globalRequestsPerMinute = Constants.defaultGlobalRpmLimit,
    this.adaptiveTpmEnabled = Constants.defaultAdaptiveTpmEnabled,
    this.enabled = true,
  });

  // ————————————————————————————————————————————
  // 入口级限流（IP / 全局），在读取请求体之前调用
  // ————————————————————————————————————————————

  RateLimitResult checkInbound(String clientIp) {
    if (!enabled) return const RateLimitResult.allow();

    if (globalRequestsPerMinute > 0) {
      if (_globalWindow.count() >= globalRequestsPerMinute) {
        _deny('global');
        return RateLimitResult.deny(
          'global',
          retryAfterSeconds: _globalWindow.retryAfterSeconds(),
          message: '全局请求速率已达上限（$globalRequestsPerMinute/分钟）',
        );
      }
    }

    if (requestsPerMinutePerIp > 0 && clientIp.isNotEmpty) {
      final w = _ipWindows.putIfAbsent(
          clientIp, () => SlidingWindow(const Duration(minutes: 1)));
      if (w.count() >= requestsPerMinutePerIp) {
        _deny('ip');
        return RateLimitResult.deny(
          'ip',
          retryAfterSeconds: w.retryAfterSeconds(),
          message: '来源 IP 请求过于频繁（$requestsPerMinutePerIp/分钟）',
        );
      }
    }
    return const RateLimitResult.allow();
  }

  /// 入口放行后记账（与 checkInbound 成对使用）
  void recordInbound(String clientIp) {
    if (!enabled) return;
    if (globalRequestsPerMinute > 0) _globalWindow.record(1);
    if (requestsPerMinutePerIp > 0 && clientIp.isNotEmpty) {
      _ipWindows
          .putIfAbsent(clientIp, () => SlidingWindow(const Duration(minutes: 1)))
          .record(1);
    }
  }

  // ————————————————————————————————————————————
  // key 级限流（RPM 令牌桶 + TPM 滑动窗口）
  // ————————————————————————————————————————————

  RateLimitResult checkKey(ApiKey key, {String model = ''}) {
    if (!enabled) return const RateLimitResult.allow();

    final effTpmLimit = _effectiveTpmLimit(key, model);
    if (effTpmLimit != null && effTpmLimit > 0) {
      final tw = _keyTokenWindows[key.id];
      final used = tw?.sum() ?? 0;
      if (used >= effTpmLimit) {
        _deny('key_tpm');
        return RateLimitResult.deny(
          'key_tpm',
          retryAfterSeconds: tw?.retryAfterSeconds() ?? 1,
          message: 'Key ${key.name} 的 token 速率已达上限',
        );
      }
    }

    final rpm = key.maxRequestsPerMinute;
    if (rpm <= 0) return const RateLimitResult.allow();
    final bucket = _bucketFor(key);
    // 只做探测，不消耗（真正消耗在 consumeKey）
    final probe = TokenBucket(
      capacity: bucket.capacity,
      refillPerSec: bucket.refillPerSec,
    )..tokens = bucket.tokens;
    if (!probe.tryConsume()) {
      _deny('key_rpm');
      return RateLimitResult.deny(
        'key_rpm',
        retryAfterSeconds: bucket.waitSecondsFor(1),
        message: 'Key ${key.name} 的请求速率已达上限（$rpm/分钟）',
      );
    }
    return const RateLimitResult.allow();
  }

  /// 该 key 当前是否可用于转发（候选池过滤时调用，不消耗令牌）
  bool allows(ApiKey key, {String model = ''}) =>
      checkKey(key, model: model).allowed;

  /// 实际发起转发时扣减令牌
  bool consumeKey(ApiKey key) {
    if (!enabled) return true;
    if (key.maxRequestsPerMinute <= 0) return true;
    return _bucketFor(key).tryConsume();
  }

  /// 响应完成后记录 token 消耗（TPM 维度），并做自适应学习。
  void recordTokens(ApiKey key, int tokens, {String model = ''}) {
    if (!enabled || tokens <= 0) return;
    final tw = _keyTokenWindows
        .putIfAbsent(key.id, () => SlidingWindow(const Duration(minutes: 1)));
    tw.record(tokens);

    // —— 自适应挡板：加性增（AIMD 的 AI：Additive Increase）——
    // 每当无 429 的用量记录累计超过一个窗口，试探性小幅上调学到的上限，
    // 让挡板逐步贴近上游真实上限（更充分地利用额度）。
    if (adaptiveTpmEnabled) {
      final keyed = '${key.id}|$model';
      if (_learnedTpm.containsKey(keyed)) {
        final stable = (_tpmStableMs[keyed] ?? 0) + tokens;
        // 每累计约 0.75 个窗口（45s）的用量做一次加性增
        if (stable >= (60 * 1000 * 3 / 4)) {
          _tpmStableMs[keyed] = 0;
          final learned = _learnedTpm[keyed]!;
          final bumped = (learned * (1 + Constants.tpmAimdUp)).round();
          if (bumped > learned) {
            _learnedTpm[keyed] = bumped;
          }
        } else {
          _tpmStableMs[keyed] = stable;
        }
      }
    }
  }

  // ————————————————————————————————————————————
  // 自适应 TPM 挡板（消除上游 TPM 限流造成的中断）
  // ————————————————————————————————————————————

  /// 计算该 key+model 应使用的 TPM 上限（token/分钟），返回 null 表示不限。
  ///
  /// 优先取用户配置的 [tokensPerMinutePerKey]（硬拦）；若未配置（0）且
  /// 自适应挡板开启，则取「从上游 429 学到的上限 × 余量系数」作为软挡板。
  int? _effectiveTpmLimit(ApiKey key, String model) {
    if (tokensPerMinutePerKey > 0) return tokensPerMinutePerKey;
    if (adaptiveTpmEnabled) {
      final learned = _learnedTpm['${key.id}|$model'];
      if (learned != null && learned > 0) {
        // 留出余量，避免同一窗口再撞限；乘性减已在下调时埋入，这里再兜底
        return (learned * 0.95).floor();
      }
    }
    return null;
  }

  /// 上游返回了 TPM 限流（429）时调用：把当次窗口用量视为「撞线点」，
  /// 用乘性减（AIMD 的 MD：Multiplicative Decrease）快速把学到的上限压下来。
  ///
  /// [usageThisWindow] 为本次 429 前窗口内已累计的 token 用量；若拿不到
  /// 具体值可传 0，此时以当前学到的上限做保守下调。
  void recordUpstreamTpmLimit(ApiKey key, String model, int usageThisWindow) {
    if (!adaptiveTpmEnabled) return;
    final keyed = '${key.id}|$model';
    final current = _learnedTpm[keyed];
    // 以「窗口用量」为依据计算撞线点；无用量信息则用当前学习值
    final base = usageThisWindow > 0 ? usageThisWindow : (current ?? 0);
    if (base <= 0) return;
    final reduced = (base * Constants.tpmAimdDown).round();
    if (reduced < 1) return;
    // 乘性减应显著低于当前挡板，避免抖动；否则取更保守的当前值×0.85
    final learned = current == null || reduced < current ? reduced : (current * 0.85).round();
    _learnedTpm[keyed] = learned > 0 ? learned : 1;
    _tpmStableMs[keyed] = 0; // 刚降过，重置稳定计时
  }

  /// 当前 TPM 滑动窗口已消耗的 token 数（供诊断）。
  int tpmUsed(ApiKey key) => _keyTokenWindows[key.id]?.sum() ?? 0;

  /// 判断请求方是否触发了「可恢复的 TPM 限流」（供代理层决定是否等待重试同 key）。
  ///
  /// [statusCode] 为 429 且 [body] 命中 TPM/限流关键词时视为可恢复；
  /// 其它（如配额耗尽、真正的封禁类 429）返回 false，交由上层按失败处理。
  static bool isRecoverableTpmLimit(int statusCode, String body) {
    if (statusCode != 429) return false;
    final b = body.toLowerCase();
    for (final kw in Constants.tpmRecoverableKeywords) {
      if (b.contains(kw)) return true;
    }
    return false;
  }

  /// 当前 TPM 窗口距可用还需等待的毫秒数（0 表示窗口已有空出/已可重试）。
  int tpmWaitMillis(ApiKey key, {int nowMs = 0}) {
    final tw = _keyTokenWindows[key.id];
    if (tw == null) return 0;
    final now = nowMs != 0 ? nowMs : DateTime.now().millisecondsSinceEpoch;
    return tw.retryAfterSeconds(nowMs: now) * 1000;
  }

  /// 清除某个 key 的学习状态（删除 key / 更新 key 后调用，避免残留旧上限）。
  void resetLearn(ApiKey key) {
    final prefix = '${key.id}|';
    _learnedTpm.removeWhere((k, _) => k.startsWith(prefix));
    _tpmStableMs.removeWhere((k, _) => k.startsWith(prefix));
  }

  TokenBucket _bucketFor(ApiKey key) {
    final rpm = key.maxRequestsPerMinute;
    final refill = rpm / 60.0;
    final capacity = rpm * burstMultiplier;
    final existing = _keyBuckets[key.id];
    // key 的 RPM 被修改后重建桶
    if (existing == null ||
        (existing.refillPerSec - refill).abs() > 0.0001 ||
        (existing.capacity - capacity).abs() > 0.0001) {
      final b = TokenBucket(capacity: capacity, refillPerSec: refill);
      _keyBuckets[key.id] = b;
      return b;
    }
    return existing;
  }

  void _deny(String dimension) {
    denials[dimension] = (denials[dimension] ?? 0) + 1;
  }

  /// 当前观测值（供统计与调试）
  Map<String, dynamic> snapshot() => {
        'enabled': enabled,
        'global_last_minute': _globalWindow.count(),
        'tracked_ips': _ipWindows.length,
        'tracked_keys': _keyBuckets.length,
        'denials': Map<String, int>.from(denials),
        'limits': {
          'burst_multiplier': burstMultiplier,
          'tokens_per_minute_per_key': tokensPerMinutePerKey,
          'adaptive_tpm_enabled': adaptiveTpmEnabled,
          'learned_tpm_entries': _learnedTpm.length,
          'requests_per_minute_per_ip': requestsPerMinutePerIp,
          'global_requests_per_minute': globalRequestsPerMinute,
        },
      };

  void reset() {
    _keyBuckets.clear();
    _keyTokenWindows.clear();
    _ipWindows.clear();
    _globalWindow.clear();
    _learnedTpm.clear();
    _tpmStableMs.clear();
    denials.clear();
  }
}
