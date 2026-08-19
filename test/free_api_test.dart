import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/free_provider.dart';
import 'package:relaygo/services/free_api_service.dart';

const _sampleJson = '''
{
  "version": "2.9.0",
  "generated": "2026-08-14",
  "source": "https://github.com/pacocartones/free-llm-api-hub",
  "note": "Canonical dataset",
  "providers": [
    {
      "slug": "google-gemini",
      "name": "Google Gemini API (AI Studio)",
      "category": "ongoing",
      "free_type": "renewing-quota",
      "free_tier": "Gemini 2.5 Flash, 2.5 Flash-Lite",
      "rate_limits": "5-30 RPM",
      "notes": "Free-tier prompts may be used",
      "best_for": "The only frontier-class model with a genuine free tier",
      "modalities": ["text", "vision", "embeddings", "audio"],
      "models_free": ["gemini-2.5-flash", "gemini-2.5-pro"],
      "expires": null,
      "docs_url": "https://ai.google.dev/gemini-api/docs/rate-limits",
      "phone_required": false,
      "card_required": false,
      "commercial_ok": true,
      "openai_compatible": true,
      "openai_base_url": "https://generativelanguage.googleapis.com/v1beta/openai/",
      "env_key": "GEMINI_API_KEY",
      "verified": true,
      "last_verified": "2026-08-02"
    },
    {
      "slug": "cerebras",
      "name": "Cerebras",
      "category": "trial",
      "free_type": "trial-credit",
      "free_tier": "\$5 in free credits",
      "rate_limits": "5 RPM",
      "notes": "Credits expire 30 days",
      "best_for": "Fastest tokens/sec",
      "modalities": ["text"],
      "models_free": ["gpt-oss-120b"],
      "expires": "30 days",
      "docs_url": "https://inference-docs.cerebras.ai",
      "phone_required": null,
      "card_required": true,
      "commercial_ok": true,
      "openai_compatible": true,
      "openai_base_url": "https://api.cerebras.ai/v1",
      "env_key": "CEREBRAS_API_KEY",
      "verified": true,
      "last_verified": "2026-08-02"
    }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FreeProvider 解析与中文化', () {
    final dataset = FreeApiDataset.fromJson(
        Map<String, dynamic>.from(jsonDecode(_sampleJson) as Map));

    test('顶层元数据解析', () {
      expect(dataset.version, '2.9.0');
      expect(dataset.generated, '2026-08-14');
      expect(dataset.providers.length, 2);
    });

    test('provider 基础字段解析', () {
      final p = dataset.providers.first;
      expect(p.slug, 'google-gemini');
      expect(p.name, 'Google Gemini API (AI Studio)');
      expect(p.category, 'ongoing');
      expect(p.freeType, 'renewing-quota');
      expect(p.freeTier, contains('Gemini 2.5 Flash'));
      expect(p.modalities, contains('vision'));
      expect(p.modelsFree, contains('gemini-2.5-pro'));
      expect(p.verified, isTrue);
      expect(p.lastVerified, '2026-08-02');
    });

    test('中文化标签映射', () {
      final ongoing = dataset.providers.first;
      expect(ongoing.categoryLabel, '持续免费');
      expect(ongoing.freeTypeLabel, '周期性刷新配额');
      expect(ongoing.modalitiesLabel, contains('文本'));
      expect(ongoing.modalitiesLabel, contains('视觉/多模态'));
      expect(ongoing.verifiedLabel, '已核实');
      expect(ongoing.expiresLabel, '无过期时间');
      expect(ongoing.commercialOk, isTrue);

      final trial = dataset.providers[1];
      expect(trial.categoryLabel, '试用额度');
      expect(trial.freeTypeLabel, '一次性试用额度');
      expect(trial.expiresLabel, '30 days');
      expect(FreeProvider.boolLabel(trial.phoneRequired), '未说明');
      expect(FreeProvider.boolLabel(trial.cardRequired), '是');
    });

    test('国旗图标映射', () {
      final gemini = dataset.providers.first;
      expect(gemini.countryCode, 'US');
      expect(gemini.flagEmoji, '🇺🇸');

      final cerebras = dataset.providers[1];
      expect(cerebras.countryCode, 'US');
      expect(cerebras.flagEmoji, '🇺🇸');

      // 未知国家 → 地球图标
      final unknown = FreeProvider.fromJson({
        'slug': 'some-unknown-provider',
        'name': 'Unknown',
        'category': 'ongoing',
        'free_type': 'perpetual',
      });
      expect(unknown.countryCode, '');
      expect(unknown.flagEmoji, '🌐');
    });

    test('国家映射覆盖全部已知 slug', () {
      // 抽样验证几个代表性提供商
      final checks = {
        'google-gemini': 'US',
        'cohere': 'CA',
        'mistral': 'FR',
        'siliconflow': 'CN',
        'zai-glm': 'CN',
        'ai21': 'IL',
        'upstage': 'KR',
        'typhoon': 'TH',
        'sarvam-ai': 'IN',
      };
      checks.forEach((slug, code) {
        final p = FreeProvider.fromJson({'slug': slug, 'name': slug});
        expect(p.countryCode, code, reason: 'slug=$slug 应映射到 $code');
      });
    });
  });

  group('FreeApiService 缓存与刷新', () {
    late Box<dynamic> box;
    late FreeApiService service;

    setUpAll(() async {
      final tmp = await Directory.systemTemp.createTemp('free_api_test');
      Hive.init(tmp.path);
    });

    setUp(() async {
      box = await Hive.openBox('test_free_api');
      await box.clear();
    });

    tearDown(() async {
      await box.close();
    });

    test('首次刷新：拉取远端并写入缓存', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(), Constants.freeApiFeedUrl);
        return http.Response(_sampleJson, 200,
            headers: {'content-type': 'application/json'});
      });
      service = FreeApiService(box: box, httpClient: client);

      expect(service.cached, isNull);
      expect(service.isStale, isTrue);

      final ok = await service.refresh();
      expect(ok, isTrue);
      expect(service.cached, isNotNull);
      expect(service.cached!.providers.length, 2);
      expect(service.cachedAt, isNotNull);
      expect(service.isStale, isFalse);
    });

    test('刷新失败：保留旧缓存（离线兜底）', () async {
      final client = MockClient((req) async => http.Response('err', 500));
      service = FreeApiService(box: box, httpClient: client);

      // 先成功一次
      final okClient = MockClient(
          (req) async => http.Response(_sampleJson, 200));
      final s1 = FreeApiService(box: box, httpClient: okClient);
      await s1.refresh();

      // 再失败
      final ok = await service.refresh();
      expect(ok, isFalse);
      expect(service.cached, isNotNull); // 旧缓存仍在
      expect(service.lastRefresh!.ok, isFalse);
    });

    test('ensureFresh：缓存未过期直接返回，不发请求', () async {
      var requests = 0;
      final client = MockClient((req) async {
        requests++;
        return http.Response(_sampleJson, 200);
      });
      service = FreeApiService(box: box, httpClient: client);
      await service.refresh();
      expect(requests, 1);

      final dataset = await service.ensureFresh();
      expect(requests, 1); // 未过期，不再请求
      expect(dataset.providers.length, 2);
    });

    test('ensureFresh：缓存过期时后台刷新', () async {
      final client = MockClient((req) async {
        return http.Response(_sampleJson, 200);
      });
      service = FreeApiService(box: box, httpClient: client);
      await service.refresh();

      // 人为把时间戳改到 25 小时前
      await box.put(Constants.freeApiCacheTimeKey,
          DateTime.now().millisecondsSinceEpoch -
              const Duration(hours: 25).inMilliseconds);
      expect(service.isStale, isTrue);

      final dataset = await service.ensureFresh();
      expect(dataset.providers.length, 2);
      expect(service.isStale, isFalse); // 已刷新
    });
  });
}
