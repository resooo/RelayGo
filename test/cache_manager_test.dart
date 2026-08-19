import 'package:flutter_test/flutter_test.dart';
import 'package:relaygo/services/cache_manager.dart';

void main() {
  group('CacheManager 键与可缓存判定', () {
    test('相同请求生成相同键，不同请求生成不同键', () {
      final a = CacheManager.buildKey(
        method: 'POST',
        path: '/v1/chat/completions',
        query: 'x=1',
        provider: 'openai',
        body: [1, 2, 3],
      );
      final b = CacheManager.buildKey(
        method: 'POST',
        path: '/v1/chat/completions',
        query: 'x=1',
        provider: 'openai',
        body: [1, 2, 3],
      );
      final c = CacheManager.buildKey(
        method: 'POST',
        path: '/v1/chat/completions',
        query: 'x=2',
        provider: 'openai',
        body: [1, 2, 3],
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('仅 2xx 非流式 GET/POST 可缓存', () {
      final cm = CacheManager(enabled: true);
      expect(
          cm.isCacheable(
              method: 'GET', statusCode: 200, streaming: false, bodyBytes: 10),
          isTrue);
      expect(
          cm.isCacheable(
              method: 'POST', statusCode: 200, streaming: false, bodyBytes: 10),
          isTrue);
      expect(
          cm.isCacheable(
              method: 'GET', statusCode: 500, streaming: false, bodyBytes: 10),
          isFalse); // 非 2xx
      expect(
          cm.isCacheable(
              method: 'GET', statusCode: 200, streaming: true, bodyBytes: 10),
          isFalse); // 流式
      expect(
          cm.isCacheable(
              method: 'DELETE', statusCode: 200, streaming: false, bodyBytes: 10),
          isFalse); // 非 GET/POST
      expect(
          cm.isCacheable(
              method: 'GET',
              statusCode: 200,
              streaming: false,
              bodyBytes: 2 * 1024 * 1024),
          isFalse); // 超体积
    });

    test('未启用时不缓存', () {
      final cm = CacheManager(enabled: false);
      expect(
          cm.isCacheable(
              method: 'GET', statusCode: 200, streaming: false, bodyBytes: 10),
          isFalse);
      expect(cm.get('whatever'), isNull);
    });
  });

  group('CacheManager 读写与淘汰', () {
    test('put/get 往返与 HIT 标记', () {
      final cm = CacheManager(enabled: true, ttl: const Duration(seconds: 10));
      expect(cm.get('k1'), isNull);
      cm.put('k1', statusCode: 200, headers: {'x': '1'}, body: [9, 9], provider: 'openai');
      final hit = cm.get('k1');
      expect(hit, isNotNull);
      expect(hit!.statusCode, 200);
      expect(hit.body, [9, 9]);
      expect(hit.provider, 'openai');
      expect(cm.stats.hits, 1);
      expect(cm.stats.misses, 1); // 首个 get('k1') 未命中记一次 miss
    });

    test('TTL 过期后读取返回 null', () {
      final cm = CacheManager(enabled: true, ttl: const Duration(milliseconds: 1));
      cm.put('k', statusCode: 200, headers: {}, body: [1], provider: '');
      // 等待过期
      return Future.delayed(const Duration(milliseconds: 5), () {
        expect(cm.get('k'), isNull);
        expect(cm.stats.expirations, 1);
      });
    });

    test('超出条目上限时按 LRU 淘汰最冷', () {
      final cm = CacheManager(enabled: true, maxEntries: 2);
      cm.put('a', statusCode: 200, headers: {}, body: [1], provider: '');
      cm.put('b', statusCode: 200, headers: {}, body: [1], provider: '');
      cm.get('a'); // a 变热
      cm.put('c', statusCode: 200, headers: {}, body: [1], provider: ''); // 触发淘汰
      expect(cm.size, 2);
      expect(cm.get('b'), isNull); // b 是最冷，被淘汰
      expect(cm.get('a'), isNotNull);
      expect(cm.get('c'), isNotNull);
      expect(cm.stats.evictions, isNot(0));
    });
  });
}
