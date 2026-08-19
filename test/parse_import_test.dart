import 'package:relaygo/screens/key_import_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseImport', () {
    test('空输入返回空列表', () {
      expect(parseImport('   \n  '), isEmpty);
    });

    test('JSON 数组：保留 provider/key/name/note/base_url', () {
      const text = '''
      [
        {"provider":"openai","key":"sk-abc","name":"账号A","note":"免费","base_url":"https://x.com"},
        {"provider":"azure","key":"abc123","name":"账号B"}
      ]
      ''';
      final rows = parseImport(text);
      expect(rows.length, 2);
      expect(rows[0]['provider'], 'openai');
      expect(rows[0]['key'], 'sk-abc');
      expect(rows[0]['name'], '账号A');
      expect(rows[0]['note'], '免费');
      expect(rows[0]['base_url'], 'https://x.com');
      expect(rows[1]['name'], '账号B');
      expect(rows[1]['note'], '');
    });

    test('JSON 数组：保留导出扩展字段（往返兼容）', () {
      const text = '''
      [
        {"provider":"openai","provider_id":"openai","key":"sk-abc","name":"账号A",
         "note":"免费","base_url":"https://x.com","group":"g1","priority":"50",
         "weight":"2","max_requests_per_minute":"30","daily_quota":"500000"}
      ]
      ''';
      final rows = parseImport(text);
      expect(rows.length, 1);
      expect(rows[0]['provider_id'], 'openai');
      expect(rows[0]['group'], 'g1');
      expect(rows[0]['priority'], '50');
      expect(rows[0]['weight'], '2');
      expect(rows[0]['max_requests_per_minute'], '30');
      expect(rows[0]['daily_quota'], '500000');
    });

    test('文本逗号分隔：provider,key,name,note', () {
      const text = 'openai,sk-xxx,账号A,免费额度\n anthropic,sk-ant,账号B,';
      final rows = parseImport(text);
      expect(rows.length, 2);
      expect(rows[0], {
        'provider': 'openai',
        'key': 'sk-xxx',
        'name': '账号A',
        'note': '免费额度',
      });
      expect(rows[1]['note'], '');
    });

    test('文本空白分隔同样生效', () {
      const text = 'openai sk-xxx 账号A';
      final rows = parseImport(text);
      expect(rows.length, 1);
      expect(rows[0]['key'], 'sk-xxx');
      expect(rows[0]['name'], '账号A');
    });

    test('不足两段的行被跳过', () {
      const text = 'onlyone\nopenai,sk-xxx';
      final rows = parseImport(text);
      expect(rows.length, 1);
      expect(rows[0]['provider'], 'openai');
    });
  });
}
