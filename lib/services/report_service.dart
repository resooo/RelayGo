import 'dart:convert';

import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/request_log.dart';
import 'package:relaygo/services/cache_manager.dart';
import 'package:relaygo/services/log_service.dart';

/// 报表周期
enum ReportPeriod { day, week, month, custom }

extension ReportPeriodX on ReportPeriod {
  String get name => toString().split('.').last;

  String get label {
    switch (this) {
      case ReportPeriod.day:
        return '日报';
      case ReportPeriod.week:
        return '周报';
      case ReportPeriod.month:
        return '月报';
      case ReportPeriod.custom:
        return '自定义';
    }
  }

  /// 周期天数（custom 由调用方指定）
  int get days {
    switch (this) {
      case ReportPeriod.day:
        return 1;
      case ReportPeriod.week:
        return 7;
      case ReportPeriod.month:
        return 30;
      case ReportPeriod.custom:
        return 0;
    }
  }
}

/// 单日汇总（趋势曲线的一个点）
class DailyBucket {
  final String date; // yyyy-MM-dd
  final int requests;
  final int errors;
  final int tokens;
  final int avgDurationMs;
  final int cacheHits;

  const DailyBucket({
    required this.date,
    this.requests = 0,
    this.errors = 0,
    this.tokens = 0,
    this.avgDurationMs = 0,
    this.cacheHits = 0,
  });

  double get errorRate => requests == 0 ? 0 : errors / requests;

  Map<String, dynamic> toJson() => {
        'date': date,
        'requests': requests,
        'errors': errors,
        'tokens': tokens,
        'avg_duration_ms': avgDurationMs,
        'cache_hits': cacheHits,
        'error_rate': errorRate,
      };
}

/// 排行项
class RankedItem {
  final String name;
  final int count;
  final int tokens;

  const RankedItem(this.name, this.count, {this.tokens = 0});

  Map<String, dynamic> toJson() =>
      {'name': name, 'count': count, 'tokens': tokens};
}

/// 环比对比（本期 vs 上期）
class PeriodDelta {
  final int current;
  final int previous;

  const PeriodDelta(this.current, this.previous);

  int get diff => current - previous;

  /// 变化率；上期为 0 时，本期有值记为 1.0（+100%）
  double get changeRate {
    if (previous == 0) return current == 0 ? 0 : 1.0;
    return (current - previous) / previous;
  }

  bool get isUp => diff > 0;

  Map<String, dynamic> toJson() => {
        'current': current,
        'previous': previous,
        'diff': diff,
        'change_rate': changeRate,
      };
}

/// 一份完整统计报表
class UsageReport {
  final ReportPeriod period;
  final int fromMs;
  final int toMs;
  final LogStats stats;
  final List<DailyBucket> daily;
  final List<RankedItem> topModels;
  final List<RankedItem> topKeys;
  final List<RankedItem> topProviders;
  final PeriodDelta requestsDelta;
  final PeriodDelta tokensDelta;
  final PeriodDelta errorsDelta;
  final int cachedRequests;
  final Map<String, int> rateLimitedByDimension;
  final CacheStats? cacheStats;
  final int generatedAt;

  const UsageReport({
    required this.period,
    required this.fromMs,
    required this.toMs,
    required this.stats,
    required this.daily,
    required this.topModels,
    required this.topKeys,
    required this.topProviders,
    required this.requestsDelta,
    required this.tokensDelta,
    required this.errorsDelta,
    required this.generatedAt,
    this.cachedRequests = 0,
    this.rateLimitedByDimension = const {},
    this.cacheStats,
  });

  DateTime get from => DateTime.fromMillisecondsSinceEpoch(fromMs);
  DateTime get to => DateTime.fromMillisecondsSinceEpoch(toMs);

  /// 缓存命中率（基于日志中的 cached 标记）
  double get cacheHitRate =>
      stats.total == 0 ? 0 : cachedRequests / stats.total;

  Map<String, dynamic> toJson() => {
        'period': period.name,
        'from': fromMs,
        'to': toMs,
        'generated_at': generatedAt,
        'summary': {
          'requests': stats.total,
          'errors': stats.errors,
          'error_rate': stats.errorRate,
          'success_rate': stats.successRate,
          'tokens': stats.totalTokens,
          'prompt_tokens': stats.promptTokens,
          'completion_tokens': stats.completionTokens,
          'avg_duration_ms': stats.avgDurationMs,
          'p95_duration_ms': stats.p95DurationMs,
          'cached_requests': cachedRequests,
          'cache_hit_rate': cacheHitRate,
        },
        'delta': {
          'requests': requestsDelta.toJson(),
          'tokens': tokensDelta.toJson(),
          'errors': errorsDelta.toJson(),
        },
        'daily': daily.map((d) => d.toJson()).toList(),
        'top_models': topModels.map((e) => e.toJson()).toList(),
        'top_keys': topKeys.map((e) => e.toJson()).toList(),
        'top_providers': topProviders.map((e) => e.toJson()).toList(),
        'by_provider': stats.byProvider,
        'by_status': stats.byStatusGroup,
        'latency_buckets': stats.latencyBuckets,
        'rate_limited': rateLimitedByDimension,
        'cache': cacheStats?.toJson(),
      };
}

/// 统计报表服务（Phase 3）
///
/// 基于 [LogService] 的原始日志做二次聚合：按天分桶趋势、环比对比、
/// Top 模型 / Key / 提供商排行、缓存与限流观测，并支持导出
/// JSON / CSV / Markdown 三种格式。
class ReportService {
  final LogService logService;
  final CacheManager? cacheManager;

  ReportService(this.logService, {this.cacheManager});

  /// 生成报表。[period] 为 custom 时用 [days] 指定天数。
  UsageReport generate({
    ReportPeriod period = ReportPeriod.day,
    int days = 0,
    DateTime? now,
    String provider = '',
  }) {
    final anchor = now ?? DateTime.now();
    final span = period == ReportPeriod.custom
        ? (days <= 0 ? 1 : days)
        : period.days;
    final capped = span > Constants.reportMaxDays ? Constants.reportMaxDays : span;

    final endOfToday = DateTime(anchor.year, anchor.month, anchor.day)
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    final start = DateTime(anchor.year, anchor.month, anchor.day)
        .subtract(Duration(days: capped - 1));
    final prevStart = start.subtract(Duration(days: capped));
    final prevEnd = start.subtract(const Duration(milliseconds: 1));

    final filter = LogFilter(
      sinceMs: start.millisecondsSinceEpoch,
      untilMs: endOfToday.millisecondsSinceEpoch,
      provider: provider,
    );
    final logs = logService.query(filter);
    final prevLogs = logService.query(LogFilter(
      sinceMs: prevStart.millisecondsSinceEpoch,
      untilMs: prevEnd.millisecondsSinceEpoch,
      provider: provider,
    ));

    final stats = logService.stats(source: logs);

    return UsageReport(
      period: period,
      fromMs: start.millisecondsSinceEpoch,
      toMs: endOfToday.millisecondsSinceEpoch,
      stats: stats,
      daily: _bucketByDay(logs, start, capped),
      topModels: _rank(logs, (l) => l.model),
      topKeys: _rank(logs, (l) => l.keyName),
      topProviders: _rank(logs, (l) => l.provider),
      requestsDelta: PeriodDelta(logs.length, prevLogs.length),
      tokensDelta: PeriodDelta(
        _sumTokens(logs),
        _sumTokens(prevLogs),
      ),
      errorsDelta: PeriodDelta(
        logs.where((l) => l.isError).length,
        prevLogs.where((l) => l.isError).length,
      ),
      cachedRequests: logs.where((l) => l.cached).length,
      rateLimitedByDimension: _countRateLimited(logs),
      cacheStats: cacheManager?.stats,
      generatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static int _sumTokens(List<RequestLog> logs) {
    var n = 0;
    for (final l in logs) {
      n += l.totalTokens;
    }
    return n;
  }

  static Map<String, int> _countRateLimited(List<RequestLog> logs) {
    final out = <String, int>{};
    for (final l in logs) {
      if (l.rateLimited.isEmpty) continue;
      out[l.rateLimited] = (out[l.rateLimited] ?? 0) + 1;
    }
    return out;
  }

  List<DailyBucket> _bucketByDay(
      List<RequestLog> logs, DateTime start, int days) {
    final byDate = <String, List<RequestLog>>{};
    for (final l in logs) {
      byDate.putIfAbsent(_dateKey(l.dateTime), () => []).add(l);
    }
    final out = <DailyBucket>[];
    for (var i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      final key = _dateKey(d);
      final items = byDate[key] ?? const <RequestLog>[];
      var errors = 0;
      var tokens = 0;
      var duration = 0;
      var hits = 0;
      for (final l in items) {
        if (l.isError) errors++;
        tokens += l.totalTokens;
        duration += l.durationMs;
        if (l.cached) hits++;
      }
      out.add(DailyBucket(
        date: key,
        requests: items.length,
        errors: errors,
        tokens: tokens,
        avgDurationMs: items.isEmpty ? 0 : duration ~/ items.length,
        cacheHits: hits,
      ));
    }
    return out;
  }

  static List<RankedItem> _rank(
    List<RequestLog> logs,
    String Function(RequestLog) selector, {
    int limit = 5,
  }) {
    final counts = <String, int>{};
    final tokens = <String, int>{};
    for (final l in logs) {
      final name = selector(l);
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
      tokens[name] = (tokens[name] ?? 0) + l.totalTokens;
    }
    final list = counts.entries
        .map((e) => RankedItem(e.key, e.value, tokens: tokens[e.key] ?? 0))
        .toList();
    list.sort((a, b) => b.count.compareTo(a.count));
    return list.length > limit ? list.sublist(0, limit) : list;
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ————————————————————————————————————————————
  // 导出
  // ————————————————————————————————————————————

  static String toJsonString(UsageReport r) =>
      const JsonEncoder.withIndent('  ').convert(r.toJson());

  /// 按天趋势导出为 CSV
  static String toCsv(UsageReport r) {
    final sb = StringBuffer();
    sb.writeln('date,requests,errors,error_rate,tokens,avg_duration_ms,cache_hits');
    for (final d in r.daily) {
      sb.writeln([
        d.date,
        d.requests,
        d.errors,
        d.errorRate.toStringAsFixed(4),
        d.tokens,
        d.avgDurationMs,
        d.cacheHits,
      ].join(','));
    }
    return sb.toString();
  }

  /// 导出为可直接粘贴的 Markdown 报表
  static String toMarkdown(UsageReport r) {
    final sb = StringBuffer();
    final s = r.stats;
    sb.writeln('# ${r.period.label}（${_dateKey(r.from)} ~ ${_dateKey(r.to)}）');
    sb.writeln();
    sb.writeln('## 概览');
    sb.writeln();
    sb.writeln('| 指标 | 本期 | 上期 | 变化 |');
    sb.writeln('| --- | --- | --- | --- |');
    sb.writeln('| 请求数 | ${s.total} | ${r.requestsDelta.previous} | '
        '${_pct(r.requestsDelta.changeRate)} |');
    sb.writeln('| Token | ${s.totalTokens} | ${r.tokensDelta.previous} | '
        '${_pct(r.tokensDelta.changeRate)} |');
    sb.writeln('| 错误数 | ${s.errors} | ${r.errorsDelta.previous} | '
        '${_pct(r.errorsDelta.changeRate)} |');
    sb.writeln('| 错误率 | ${_pct(s.errorRate, signed: false)} | - | - |');
    sb.writeln('| 平均耗时 | ${s.avgDurationMs} ms | - | - |');
    sb.writeln('| P95 耗时 | ${s.p95DurationMs} ms | - | - |');
    sb.writeln('| 缓存命中 | ${r.cachedRequests}'
        '（${_pct(r.cacheHitRate, signed: false)}） | - | - |');
    sb.writeln();

    if (r.daily.isNotEmpty) {
      sb.writeln('## 每日趋势');
      sb.writeln();
      sb.writeln('| 日期 | 请求 | 错误 | Token | 平均耗时 |');
      sb.writeln('| --- | --- | --- | --- | --- |');
      for (final d in r.daily) {
        sb.writeln('| ${d.date} | ${d.requests} | ${d.errors} | '
            '${d.tokens} | ${d.avgDurationMs} ms |');
      }
      sb.writeln();
    }

    void writeRank(String title, List<RankedItem> items) {
      if (items.isEmpty) return;
      sb.writeln('## $title');
      sb.writeln();
      sb.writeln('| 名称 | 请求数 | Token |');
      sb.writeln('| --- | --- | --- |');
      for (final i in items) {
        sb.writeln('| ${i.name} | ${i.count} | ${i.tokens} |');
      }
      sb.writeln();
    }

    writeRank('Top 模型', r.topModels);
    writeRank('Top Key', r.topKeys);
    writeRank('Top 提供商', r.topProviders);

    if (r.rateLimitedByDimension.isNotEmpty) {
      sb.writeln('## 限流触发');
      sb.writeln();
      r.rateLimitedByDimension.forEach((k, v) {
        sb.writeln('- $k：$v 次');
      });
      sb.writeln();
    }
    return sb.toString();
  }

  static String _pct(double v, {bool signed = true}) {
    final p = (v * 100).toStringAsFixed(1);
    if (!signed) return '$p%';
    return v >= 0 ? '+$p%' : '$p%';
  }
}
