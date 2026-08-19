import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/models/request_log.dart';
import 'package:relaygo/services/log_service.dart';

int _seq = 0;

void main() {
  late Box box;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('log_test');
    Hive.init(tmp.path);
    box = await Hive.openBox('logs_test');
  });

  tearDown(() async {
    await box.clear();
  });

  RequestLog _log({
    String provider = 'openai',
    int status = 200,
    String model = 'gpt-4o',
    int prompt = 1,
    int completion = 2,
    int duration = 100,
  }) =>
      RequestLog(
        id: 'log_${_seq++}',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        method: 'POST',
        path: '/v1/chat/completions',
        provider: provider,
        keyMasked: 'sk-****',
        statusCode: status,
        durationMs: duration,
        model: model,
        promptTokens: prompt,
        completionTokens: completion,
      );

  test('add 后 recent 可见', () {
    final svc = LogService(box);
    svc.add(_log());
    expect(svc.recent.length, 1);
    svc.dispose();
  });

  test('flush 后 query / stats 可见', () async {
    final svc = LogService(box);
    svc.add(_log(provider: 'openai', status: 200, prompt: 10, completion: 20, duration: 100));
    svc.add(_log(provider: 'anthropic', status: 500, prompt: 5, completion: 5, duration: 300));
    await svc.flush();

    expect(svc.query(LogFilter.none).length, 2);
    expect(svc.query(const LogFilter(provider: 'anthropic')).length, 1);
    expect(svc.query(const LogFilter(status: 'error')).length, 1);
    expect(svc.query(const LogFilter(status: '5xx')).length, 1);

    final s = svc.stats();
    expect(s.total, 2);
    expect(s.errors, 1);
    expect(s.totalTokens, 40);
    expect(s.byProvider['openai'], 1);
    expect(s.byProvider['anthropic'], 1);
    expect(s.avgDurationMs, 200);
    svc.dispose();
  });

  test('query 按 provider 过滤', () async {
    final svc = LogService(box);
    svc.add(_log(provider: 'openai'));
    svc.add(_log(provider: 'anthropic'));
    await svc.flush();
    expect(svc.query(const LogFilter(provider: 'anthropic')).length, 1);
    svc.dispose();
  });

  test('query 按状态过滤（错误）', () async {
    final svc = LogService(box);
    svc.add(_log(status: 200));
    svc.add(_log(status: 500));
    await svc.flush();
    expect(svc.query(const LogFilter(status: 'error')).length, 1);
    expect(svc.query(const LogFilter(status: '5xx')).length, 1);
    svc.dispose();
  });

  test('cleanup 按条数上限裁剪', () async {
    final svc = LogService(box, maxEntries: 2);
    svc.add(_log());
    svc.add(_log());
    svc.add(_log());
    await svc.flush();
    expect(box.length, 2);
    svc.dispose();
  });

  test('toCsv 导出含表头与行', () {
    final csv = LogService.toCsv([_log(model: 'gpt-4o')]);
    expect(csv.split('\n').first, contains('prompt_tokens'));
    expect(csv, contains('gpt-4o'));
  });
}
