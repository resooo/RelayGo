import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/models/request_log.dart';
import 'package:relaygo/services/cache_manager.dart';
import 'package:relaygo/services/log_service.dart';
import 'package:relaygo/services/report_service.dart';

RequestLog _log(int i,
    {String provider = 'openai',
    String model = 'gpt-4o-mini',
    int status = 200,
    int prompt = 10,
    int completion = 20,
    bool cached = false,
    String rateLimited = '',
    int? ts}) {
  final now = DateTime.now();
  return RequestLog(
    id: 'log-$i',
    timestamp: ts ?? now.millisecondsSinceEpoch - i * 1000,
    method: 'POST',
    path: '/v1/chat/completions',
    provider: provider,
    keyName: 'key-$i',
    keyMasked: 'sk-***',
    statusCode: status,
    durationMs: 100 + i,
    promptTokens: prompt,
    completionTokens: completion,
    model: model,
    cached: cached,
    rateLimited: rateLimited,
  );
}

void main() {
  late Box box;
  late LogService logService;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('report_test');
    Hive.init(tmp.path);
    await Hive.openBox('request_logs_report');
    box = Hive.box('request_logs_report');
  });

  setUp(() async {
    await box.clear();
    // 注入当日日志：10 条成功（含 2 条缓存命中）、2 条错误、1 条限流
    final seeds = <RequestLog>[
      for (var i = 0; i < 8; i++)
        _log(i, provider: i % 2 == 0 ? 'openai' : 'anthropic'),
      _log(8, cached: true, provider: 'openai'),
      _log(9, cached: true, provider: 'openai'),
      _log(10, status: 500, provider: 'openai'),
      _log(11, status: 429, provider: 'anthropic', rateLimited: 'key_rpm'),
    ];
    for (final l in seeds) {
      box.put(l.id, l.toJson());
    }
    logService = LogService(box);
  });

  test('日报概览统计正确', () {
    final report = ReportService(logService).generate(period: ReportPeriod.day);
    expect(report.stats.total, 12);
    expect(report.stats.errors, 2); // 500 + 429
    expect(report.cachedRequests, 2);
    expect(report.cacheHitRate, closeTo(2 / 12, 0.001));
    expect(report.stats.totalTokens, (10 + 20) * 12);
  });

  test('每日分桶覆盖当天', () {
    final report = ReportService(logService).generate(period: ReportPeriod.day);
    expect(report.daily, isNotEmpty);
    final today = report.daily.firstWhere(
        (d) => d.date == _today(), orElse: () => report.daily.last);
    expect(today.requests, 12);
  });

  test('Top 排行非空', () {
    final report = ReportService(logService).generate(period: ReportPeriod.day);
    expect(report.topModels, isNotEmpty);
    expect(report.topProviders, isNotEmpty);
    expect(report.topKeys, isNotEmpty);
  });

  test('限流维度观测', () {
    final report = ReportService(logService).generate(period: ReportPeriod.day);
    expect(report.rateLimitedByDimension['key_rpm'], 1);
  });

  test('环比：无上期数据时上期为 0', () {
    final report = ReportService(logService).generate(period: ReportPeriod.day);
    expect(report.requestsDelta.previous, 0);
    expect(report.requestsDelta.current, 12);
  });

  test('导出三种格式非空', () {
    final report = ReportService(logService).generate(period: ReportPeriod.day);
    expect(ReportService.toJsonString(report), isNotEmpty);
    expect(ReportService.toCsv(report), contains('date,requests'));
    expect(ReportService.toMarkdown(report), contains('# 日报'));
  });

  test('缓存统计注入', () {
    final cm = CacheManager(enabled: true, maxEntries: 500);
    cm.put('k', statusCode: 200, headers: {}, body: [1, 2, 3], provider: 'openai');
    cm.get('k');
    final report =
        ReportService(logService, cacheManager: cm).generate(period: ReportPeriod.day);
    expect(report.cacheStats, isNotNull);
    expect(report.cacheStats!.hits, 1);
  });
}

String _today() {
  final d = DateTime.now();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}
