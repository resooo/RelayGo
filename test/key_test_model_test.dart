import 'package:flutter_test/flutter_test.dart';
import 'package:relaygo/models/key_test.dart';

KeyTestRecord _rec(String name, KeyTestOutcome outcome) => KeyTestRecord(
      id: 'id-$name',
      provider: 'openai',
      name: name,
      note: 'note-$name',
      maskedKey: 'sk-$name••••',
      outcome: outcome,
    );

void main() {
  group('KeyTestOutcome', () {
    test('valid / invalid / timeout / failure 构造正确', () {
      expect(KeyTestOutcome.valid().ok, isTrue);
      final inv = KeyTestOutcome.invalid(401, '');
      expect(inv.ok, isFalse);
      expect(inv.status, KeyTestStatus.invalid);
      expect(inv.httpStatus, 401);
      expect(inv.error, contains('401 Unauthorized'));
      expect(KeyTestOutcome.timeout().status, KeyTestStatus.timeout);
      expect(KeyTestOutcome.failure('boom').status, KeyTestStatus.error);
    });

    test('KeyTestStatusX.fromString 解析', () {
      expect(KeyTestStatusX.fromString('valid'), KeyTestStatus.valid);
      expect(KeyTestStatusX.fromString('invalid'), KeyTestStatus.invalid);
      expect(KeyTestStatusX.fromString(null), isNull);
      expect(KeyTestStatusX.fromString('nope'), isNull);
    });
  });

  group('BatchTestSummary', () {
    final summary = BatchTestSummary([
      _rec('a', KeyTestOutcome.valid()),
      _rec('b', KeyTestOutcome.invalid(401, '')),
      _rec('c', KeyTestOutcome.invalid(403, '')),
      _rec('d', KeyTestOutcome.timeout()),
      _rec('e', KeyTestOutcome.failure('dns')),
      _rec('f', KeyTestOutcome.valid()),
    ]);

    test('计数正确', () {
      expect(summary.total, 6);
      expect(summary.validCount, 2);
      expect(summary.invalidCount, 2);
      expect(summary.timeoutCount, 1);
      expect(summary.errorCount, 1);
      expect(summary.failed.length, 4); // b,c,d,e
    });

    test('toText 汇总含有效/无效/超时与失败列表', () {
      final t = summary.toText();
      expect(t, contains('✅ 有效：2 个'));
      expect(t, contains('❌ 无效：2 个'));
      expect(t, contains('⚠️ 超时：1 个'));
      expect(t, contains('⚠️ 异常：1 个'));
      expect(t, contains('sk-b••••'));
      expect(t, contains('401 Unauthorized'));
    });

    test('toCsv 含表头与每行', () {
      final csv = summary.toCsv();
      final lines = csv.split('\n');
      expect(lines.first, contains('provider,name,note,masked_key,status'));
      expect(lines.length, summary.total + 2); // 表头 + 空尾行
      expect(csv, contains('"sk-a••••",valid'));
    });
  });
}
