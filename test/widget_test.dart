// 核心逻辑冒烟测试（不依赖 Hive / UI，确保可独立运行）
import 'package:flutter_test/flutter_test.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/services/load_balancer.dart';
import 'package:relaygo/services/providers/provider_factory.dart';
import 'package:relaygo/utils/encryption.dart';

void main() {
  test('AES-256 加解密往返', () {
    EncryptionUtil.init(EncryptionUtil.generateMasterKeyBase64());
    const plain = 'sk-1234567890abcdef';
    final cipher = EncryptionUtil.encrypt(plain);
    expect(cipher, isNot(plain));
    expect(EncryptionUtil.decrypt(cipher), plain);
  });

  test('负载均衡仅选择 active key', () {
    final lb = LoadBalancer();
    final keys = [
      ApiKey(
          id: '1',
          provider: 'openai',
          encryptedKey: 'x',
          name: 'a',
          createdAt: 1,
          status: KeyStatus.active),
      ApiKey(
          id: '2',
          provider: 'openai',
          encryptedKey: 'y',
          name: 'b',
          createdAt: 2,
          status: KeyStatus.inactive),
    ];
    final picked = lb.pick(keys, 'round_robin');
    expect(picked?.id, '1');
  });

  test('连续失败触发冷却', () {
    final lb = LoadBalancer();
    final k = ApiKey(
        id: '1',
        provider: 'openai',
        encryptedKey: 'x',
        name: 'a',
        createdAt: 1,
        status: KeyStatus.active);
    lb.recordFailure(k);
    lb.recordFailure(k);
    lb.recordFailure(k);
    expect(k.status, KeyStatus.error);
    expect(k.cooldownUntil, isNotNull);
  });

  test('providerFor 工厂返回正确适配器', () {
    expect(providerFor(ProviderType.openai).type, ProviderType.openai);
    expect(providerFor(ProviderType.anthropic).type, ProviderType.anthropic);
    expect(providerFor(ProviderType.google).type, ProviderType.google);
    expect(providerFor(ProviderType.azure).type, ProviderType.azure);
    expect(providerFor(ProviderType.custom).type, ProviderType.custom);
  });
}
