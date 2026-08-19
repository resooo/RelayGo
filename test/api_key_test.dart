import 'package:flutter_test/flutter_test.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/key_test.dart';

void main() {
  group('ApiKey 备注与测试结果字段（REQ-001）', () {
    test('toJson / fromJson 往返包含 note / lastTested / testResult / testError',
        () {
      final k = ApiKey(
        id: 'k1',
        provider: 'openai',
        encryptedKey: 'enc',
        name: '账号A',
        note: '免费额度',
        lastTested: 1700000000000,
        testResult: 'valid',
        testError: null,
        createdAt: 0,
      );
      final json = k.toJson();
      final k2 = ApiKey.fromJson(json);
      expect(k2.note, '免费额度');
      expect(k2.lastTested, 1700000000000);
      expect(k2.testResult, 'valid');
      expect(k2.testError, isNull);
      expect(k2.lastTestStatus, KeyTestStatus.valid);
      expect(k2.tested, isTrue);
      expect(k2.lastTestedTime,
          DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('旧数据缺省字段向后兼容（note 空、未测试）', () {
      final k = ApiKey.fromJson({
        'id': 'k2',
        'provider': 'anthropic',
        'key': 'enc',
        'name': 'x',
      });
      expect(k.note, '');
      expect(k.testResult, isNull);
      expect(k.tested, isFalse);
      expect(k.lastTestStatus, isNull);
    });

    test('copyWith 支持 note 与 provider', () {
      final k = ApiKey(
        id: 'k3',
        provider: 'openai',
        encryptedKey: 'enc',
        name: 'n',
        note: '旧备注',
        createdAt: 0,
      );
      final c = k.copyWith(note: '新备注', provider: 'azure');
      expect(c.note, '新备注');
      expect(c.provider, 'azure');
      // 原对象不受影响
      expect(k.note, '旧备注');
      expect(k.provider, 'openai');
    });

    test('copyWith 支持 encryptedKey（编辑时更换 key）', () {
      final k = ApiKey(
        id: 'k4',
        provider: 'openai',
        encryptedKey: 'old',
        name: 'n',
        createdAt: 0,
      );
      final c = k.copyWith(encryptedKey: 'new');
      expect(c.encryptedKey, 'new');
    });
  });
}
