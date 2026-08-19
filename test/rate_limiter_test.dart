import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/services/key_manager.dart';
import 'package:relaygo/services/rate_limiter.dart';
import 'package:relaygo/utils/encryption.dart';

void main() {
  late KeyManager keyManager;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('rl_test');
    Hive.init(tmp.path);
    await Hive.openBox('api_keys_rl');
    keyManager = KeyManager(Hive.box('api_keys_rl'));
    EncryptionUtil.init(EncryptionUtil.generateMasterKeyBase64());
  });

  group('入口限流（IP / 全局）', () {
    test('单 IP 超过阈值返回 429', () {
      final rl = RateLimiter(
        enabled: true,
        requestsPerMinutePerIp: 2,
        globalRequestsPerMinute: 0,
      );
      expect(rl.checkInbound('1.2.3.4').allowed, isTrue);
      rl.recordInbound('1.2.3.4');
      expect(rl.checkInbound('1.2.3.4').allowed, isTrue);
      rl.recordInbound('1.2.3.4');
      final third = rl.checkInbound('1.2.3.4');
      expect(third.allowed, isFalse);
      expect(third.dimension, 'ip');
    });

    test('全局速率超过阈值拒绝', () {
      final rl = RateLimiter(
        enabled: true,
        requestsPerMinutePerIp: 0,
        globalRequestsPerMinute: 1,
      );
      expect(rl.checkInbound('9.9.9.9').allowed, isTrue);
      rl.recordInbound('9.9.9.9');
      final r = rl.checkInbound('9.9.9.9');
      expect(r.allowed, isFalse);
      expect(r.dimension, 'global');
    });

    test('维度拒绝计数进入 denials', () {
      final rl = RateLimiter(
        enabled: true,
        requestsPerMinutePerIp: 1,
      );
      rl.recordInbound('1.1.1.1');
      rl.checkInbound('1.1.1.1');
      rl.recordInbound('1.1.1.1');
      rl.checkInbound('1.1.1.1');
      expect(rl.denials['ip'], greaterThan(0));
    });
  });

  group('key 级限流（RPM 令牌桶 / TPM 滑动窗口）', () {
    test('超过 key 的 RPM 被限流', () async {
      final key = await keyManager.createKey(
        provider: 'openai',
        plainKey: 'sk-rl',
        name: 'rl-key',
        maxRpm: 2,
      );
      final rl = RateLimiter(enabled: true, burstMultiplier: 1.0);
      // consumeKey 实际扣令牌（探测用 checkKey）
      expect(rl.checkKey(key).allowed, isTrue);
      rl.consumeKey(key);
      expect(rl.checkKey(key).allowed, isTrue);
      rl.consumeKey(key);
      // 已耗尽 2 个令牌（容量=2*1.0），第三次应拒绝
      final r = rl.checkKey(key);
      expect(r.allowed, isFalse);
      expect(r.dimension, 'key_rpm');
    });

    test('TPM 滑动窗口超限拒绝', () async {
      final key = await keyManager.createKey(
        provider: 'openai',
        plainKey: 'sk-tpm',
        name: 'tpm-key',
      );
      final rl = RateLimiter(enabled: true, tokensPerMinutePerKey: 10);
      rl.recordTokens(key, 6);
      expect(rl.checkKey(key).allowed, isTrue);
      rl.recordTokens(key, 6); // 累计 12 >= 10
      final r = rl.checkKey(key);
      expect(r.allowed, isFalse);
      expect(r.dimension, 'key_tpm');
    });

    test('不启用限流一律放行', () async {
      final key = await keyManager.createKey(
        provider: 'openai',
        plainKey: 'sk-off',
        name: 'off-key',
        maxRpm: 1,
      );
      final rl = RateLimiter(enabled: false);
      expect(rl.checkInbound('1.1.1.1').allowed, isTrue);
      expect(rl.checkKey(key).allowed, isTrue);
    });
  });

  group('自适应 TPM 挡板（消除上游 TPM 限流）', () {
    test('识别可恢复 TPM 限流：429 + 关键词', () {
      expect(
        RateLimiter.isRecoverableTpmLimit(
            429, '{"error":{"type":"tokens_per_minute exceeded"}}'),
        isTrue,
      );
      expect(
        RateLimiter.isRecoverableTpmLimit(
            429, '{"error":{"type":"inference_tpm limit reached"}}'),
        isTrue,
      );
      expect(
        RateLimiter.isRecoverableTpmLimit(429, '{"error":"some other thing"}'),
        isFalse, // 429 但无 TPM 关键词 → 视为不可恢复（配额/封禁类）
      );
      expect(RateLimiter.isRecoverableTpmLimit(503, 'tpm'), isFalse);
    });

    test('上游 429 反馈会下调学到的 TPM 上限并生效', () async {
      final key = await keyManager.createKey(
        provider: 'openai',
        plainKey: 'sk-ada',
        name: 'ada-key',
      );
      // 未配置硬限（tokensPerMinutePerKey=0），自适应挡板开启
      final rl = RateLimiter(enabled: true, adaptiveTpmEnabled: true);
      // 模拟：学过其上限约 100 token/分钟
      rl.recordTokens(key, 80, model: 'gpt-4o');
      rl.recordUpstreamTpmLimit(key, 'gpt-4o', 80); // 乘性减：80*0.85≈68
      // 现在窗口内累计 80 token 已超过学到的上限 68*0.95≈64，应被挡板拒绝
      expect(rl.checkKey(key, model: 'gpt-4o').allowed, isFalse);
      // 换个模型不受影响（学习按 key+model 隔离）
      expect(rl.checkKey(key, model: 'claude-3').allowed, isTrue);
    });

    test('resetLearn 清除某个 key 的学习状态', () async {
      final key = await keyManager.createKey(
        provider: 'openai',
        plainKey: 'sk-reset',
        name: 'reset-key',
      );
      final rl = RateLimiter(enabled: true, adaptiveTpmEnabled: true);
      rl.recordTokens(key, 100, model: 'gpt-4');
      rl.recordUpstreamTpmLimit(key, 'gpt-4', 100);
      expect(rl.checkKey(key, model: 'gpt-4').allowed, isFalse);
      rl.resetLearn(key);
      expect(rl.checkKey(key, model: 'gpt-4').allowed, isTrue);
    });

    test('关闭自适应后可绕过挡板（不学习不拦截）', () async {
      final key = await keyManager.createKey(
        provider: 'openai',
        plainKey: 'sk-adapt-off',
        name: 'adapt-off',
      );
      // 关闭后不应学习、不应挡板
      final rl = RateLimiter(enabled: true, adaptiveTpmEnabled: false);
      rl.recordTokens(key, 1000, model: 'gpt-4');
      rl.recordUpstreamTpmLimit(key, 'gpt-4', 1000); // 未开启 → 不生效
      expect(rl.checkKey(key, model: 'gpt-4').allowed, isTrue);
    });
  });

  test('snapshot 反映当前观测值', () async {
    final key = await keyManager.createKey(
      provider: 'openai',
      plainKey: 'sk-snap',
      name: 'snap-key',
      maxRpm: 5,
    );
    final rl = RateLimiter(
      enabled: true,
      requestsPerMinutePerIp: 3,
      globalRequestsPerMinute: 4,
      tokensPerMinutePerKey: 100,
    );
    rl.recordInbound('2.2.2.2');
    rl.consumeKey(key);
    final snap = rl.snapshot();
    expect(snap['enabled'], isTrue);
    expect(snap['tracked_ips'], 1);
    expect(snap['tracked_keys'], 1);
    expect(snap['limits']['requests_per_minute_per_ip'], 3);
  });
}
