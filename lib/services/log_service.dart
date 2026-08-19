import 'dart:async';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/request_log.dart';

/// 日志筛选条件（需求 2.2.1：按时间、提供商、状态筛选）
class LogFilter {
  final int? sinceMs;
  final int? untilMs;
  final String provider; // 空串表示全部
  final String status; // all | success | error | 4xx | 5xx | proxy_error
  final String search; // 关键字，匹配 path/model/key 名/错误信息
  final String keyId; // 空串表示全部

  const LogFilter({
    this.sinceMs,
    this.untilMs,
    this.provider = '',
    this.status = 'all',
    this.search = '',
    this.keyId = '',
  });

  static const LogFilter none = LogFilter();

  bool get isEmpty =>
      sinceMs == null &&
      untilMs == null &&
      provider.isEmpty &&
      status == 'all' &&
      search.isEmpty &&
      keyId.isEmpty;

  bool matches(RequestLog log) {
    if (sinceMs != null && log.timestamp < sinceMs!) return false;
    if (untilMs != null && log.timestamp > untilMs!) return false;
    if (provider.isNotEmpty && log.provider != provider) return false;
    if (keyId.isNotEmpty && log.keyId != keyId) return false;

    switch (status) {
      case 'success':
        if (log.isError) return false;
        break;
      case 'error':
        if (!log.isError) return false;
        break;
      case '4xx':
        if (log.statusCode < 400 || log.statusCode >= 500) return false;
        break;
      case '5xx':
        if (log.statusCode < 500) return false;
        break;
      case 'proxy_error':
        if (log.statusCode != 0) return false;
        break;
      default:
        break;
    }

    if (search.isNotEmpty) {
      final q = search.toLowerCase();
      final hay = [
        log.path,
        log.model,
        log.provider,
        log.keyName,
        log.error ?? '',
        log.ruleName ?? '',
        '${log.statusCode}',
      ].join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  LogFilter copyWith({
    int? sinceMs,
    int? untilMs,
    String? provider,
    String? status,
    String? search,
    String? keyId,
    bool clearSince = false,
    bool clearUntil = false,
  }) {
    return LogFilter(
      sinceMs: clearSince ? null : (sinceMs ?? this.sinceMs),
      untilMs: clearUntil ? null : (untilMs ?? this.untilMs),
      provider: provider ?? this.provider,
      status: status ?? this.status,
      search: search ?? this.search,
      keyId: keyId ?? this.keyId,
    );
  }
}

/// 聚合统计结果（供统计页使用）
class LogStats {
  final int total;
  final int errors;
  final int avgDurationMs;
  final int p95DurationMs;
  final int promptTokens;
  final int completionTokens;
  final Map<String, int> byProvider;
  final Map<String, int> byModel;
  final Map<String, int> tokensByProvider;
  final Map<String, int> byStatusGroup; // 2xx/4xx/5xx/代理错误
  final List<int> byHour; // 长度 24，按小时的请求数
  final Map<String, int> latencyBuckets; // 延迟分布

  const LogStats({
    this.total = 0,
    this.errors = 0,
    this.avgDurationMs = 0,
    this.p95DurationMs = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.byProvider = const {},
    this.byModel = const {},
    this.tokensByProvider = const {},
    this.byStatusGroup = const {},
    this.byHour = const [],
    this.latencyBuckets = const {},
  });

  int get totalTokens => promptTokens + completionTokens;

  double get errorRate => total == 0 ? 0 : errors / total;

  double get successRate => total == 0 ? 0 : (total - errors) / total;
}

/// 请求日志服务（需求 2.2.1）
///
/// - 内存保留最近若干条并提供实时流，UI 可即时刷新；
/// - 批量落盘（默认 400ms 合并一次），避免高并发下逐条写盘拖慢转发；
/// - 支持筛选查询、CSV/JSON 导出、按天数与条数自动清理。
class LogService {
  final Box box;
  int maxEntries;
  int retentionDays;

  final StreamController<RequestLog> _controller =
      StreamController<RequestLog>.broadcast();
  final List<RequestLog> _memory = []; // 最新在前
  final Map<String, Map<String, dynamic>> _pending = {};
  Timer? _flushTimer;
  bool _disposed = false;

  LogService(
    this.box, {
    this.maxEntries = Constants.defaultMaxLogEntries,
    this.retentionDays = Constants.defaultLogRetentionDays,
  }) {
    // 启动时载入最近日志到内存，便于 UI 立即展示
    final loaded = all();
    _memory.addAll(loaded.take(Constants.logMemoryCap));
  }

  Stream<RequestLog> get stream => _controller.stream;

  List<RequestLog> get recent => List.unmodifiable(_memory);

  int get persistedCount => box.length + _pending.length;

  /// 记录一条日志（非阻塞：入内存 + 挂起批量写盘）
  void add(RequestLog log) {
    _memory.insert(0, log);
    if (_memory.length > Constants.logMemoryCap) _memory.removeLast();
    if (!_controller.isClosed) _controller.add(log);
    _pending[log.id] = log.toJson();
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_disposed) return;
    if (_flushTimer != null && _flushTimer!.isActive) return;
    _flushTimer = Timer(
      const Duration(milliseconds: Constants.logFlushMillis),
      () {
        flush();
      },
    );
  }

  /// 立即把挂起日志写入存储，并执行容量清理
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final batch = Map<String, Map<String, dynamic>>.from(_pending);
    _pending.clear();
    await box.putAll(batch);
    await _enforceCapacity();
  }

  /// 全部日志（最新在前）
  List<RequestLog> all() {
    final list = box.values
        .whereType<Map>()
        .map((m) => RequestLog.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  /// 按条件查询（最新在前）
  List<RequestLog> query(LogFilter filter, {int limit = 0}) {
    final list = all().where(filter.matches).toList();
    if (limit > 0 && list.length > limit) return list.sublist(0, limit);
    return list;
  }

  /// 聚合统计
  LogStats stats({LogFilter filter = LogFilter.none, List<RequestLog>? source}) {
    final logs = source ?? query(filter);
    if (logs.isEmpty) return const LogStats(byHour: <int>[]);

    var errors = 0;
    var prompt = 0;
    var completion = 0;
    final durations = <int>[];
    final byProvider = <String, int>{};
    final byModel = <String, int>{};
    final tokensByProvider = <String, int>{};
    final byStatusGroup = <String, int>{};
    final byHour = List<int>.filled(24, 0);
    final buckets = <String, int>{
      '<200ms': 0,
      '200-500ms': 0,
      '0.5-1s': 0,
      '1-3s': 0,
      '>3s': 0,
    };

    for (final l in logs) {
      if (l.isError) errors++;
      prompt += l.promptTokens;
      completion += l.completionTokens;
      durations.add(l.durationMs);
      byProvider[l.provider] = (byProvider[l.provider] ?? 0) + 1;
      if (l.model.isNotEmpty) {
        byModel[l.model] = (byModel[l.model] ?? 0) + 1;
      }
      tokensByProvider[l.provider] =
          (tokensByProvider[l.provider] ?? 0) + l.totalTokens;

      final group = l.statusCode == 0
          ? '代理错误'
          : l.statusCode >= 500
              ? '5xx'
              : l.statusCode >= 400
                  ? '4xx'
                  : '2xx';
      byStatusGroup[group] = (byStatusGroup[group] ?? 0) + 1;

      byHour[l.dateTime.hour]++;

      final d = l.durationMs;
      if (d < 200) {
        buckets['<200ms'] = buckets['<200ms']! + 1;
      } else if (d < 500) {
        buckets['200-500ms'] = buckets['200-500ms']! + 1;
      } else if (d < 1000) {
        buckets['0.5-1s'] = buckets['0.5-1s']! + 1;
      } else if (d < 3000) {
        buckets['1-3s'] = buckets['1-3s']! + 1;
      } else {
        buckets['>3s'] = buckets['>3s']! + 1;
      }
    }

    durations.sort();
    final avg = durations.reduce((a, b) => a + b) ~/ durations.length;
    final p95Index = ((durations.length - 1) * 0.95).round();

    return LogStats(
      total: logs.length,
      errors: errors,
      avgDurationMs: avg,
      p95DurationMs: durations[p95Index],
      promptTokens: prompt,
      completionTokens: completion,
      byProvider: byProvider,
      byModel: byModel,
      tokensByProvider: tokensByProvider,
      byStatusGroup: byStatusGroup,
      byHour: byHour,
      latencyBuckets: buckets,
    );
  }

  /// 自动清理：先按保留天数，再按条数上限
  Future<int> cleanup() async {
    var removed = 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (retentionDays > 0) {
      final cutoff = now - retentionDays * 24 * 3600 * 1000;
      final expired = <dynamic>[];
      for (final k in box.keys) {
        final raw = box.get(k);
        if (raw is! Map) continue;
        final ts = raw['timestamp'] as int? ?? 0;
        if (ts < cutoff) expired.add(k);
      }
      if (expired.isNotEmpty) {
        await box.deleteAll(expired);
        removed += expired.length;
      }
    }

    removed += await _enforceCapacity();
    if (removed > 0) _syncMemory();
    return removed;
  }

  /// 条数上限控制（删除最旧的）
  Future<int> _enforceCapacity() async {
    if (maxEntries <= 0 || box.length <= maxEntries) return 0;
    final entries = <List<dynamic>>[];
    for (final k in box.keys) {
      final raw = box.get(k);
      final ts = raw is Map ? (raw['timestamp'] as int? ?? 0) : 0;
      entries.add([k, ts]);
    }
    entries.sort((a, b) => (a[1] as int).compareTo(b[1] as int));
    final overflow = box.length - maxEntries;
    final toDelete = entries.take(overflow).map((e) => e[0]).toList();
    await box.deleteAll(toDelete);
    return toDelete.length;
  }

  void _syncMemory() {
    final ids = box.keys.map((k) => '$k').toSet();
    _memory.removeWhere((l) => !ids.contains(l.id) && !_pending.containsKey(l.id));
  }

  /// 清空全部日志
  Future<void> clear() async {
    _pending.clear();
    _memory.clear();
    await box.clear();
  }

  /// 导出为 CSV（需求 2.2.1 日志导出）
  static String toCsv(List<RequestLog> logs) {
    final sb = StringBuffer();
    sb.writeln(RequestLog.csvHeader.map(_csvCell).join(','));
    for (final l in logs) {
      sb.writeln(l.toCsvRow().map(_csvCell).join(','));
    }
    return sb.toString();
  }

  /// 导出为 JSON
  static String toJsonString(List<RequestLog> logs) {
    return const JsonEncoder.withIndent('  ')
        .convert(logs.map((l) => l.toJson()).toList());
  }

  static String _csvCell(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _controller.close();
  }
}
