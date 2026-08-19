import 'dart:convert';
import 'package:relaygo/utils/usage_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TokenUsage', () {
    test('merge 取各维度最大值（流式累计）', () {
      const a = TokenUsage(10, 20);
      const b = TokenUsage(15, 5);
      final m = a.merge(b);
      expect(m.promptTokens, 15);
      expect(m.completionTokens, 20);
      expect(m.total, 35);
    });
  });

  group('UsageParser.fromJsonMap', () {
    test('OpenAI usage', () {
      final u = UsageParser.fromJsonMap({
        'usage': {'prompt_tokens': 12, 'completion_tokens': 34},
      });
      expect(u.promptTokens, 12);
      expect(u.completionTokens, 34);
    });

    test('Anthropic usage（message_start 形态）', () {
      final u = UsageParser.fromJsonMap({
        'message': {
          'usage': {'input_tokens': 7, 'output_tokens': 9}
        }
      });
      expect(u.promptTokens, 7);
      expect(u.completionTokens, 9);
    });

    test('Google usageMetadata', () {
      final u = UsageParser.fromJsonMap({
        'usageMetadata': {
          'promptTokenCount': 3,
          'candidatesTokenCount': 5,
        }
      });
      expect(u.promptTokens, 3);
      expect(u.completionTokens, 5);
    });
  });

  group('UsageParser.parseBody', () {
    test('普通 JSON 对象', () {
      final body = jsonEncode({
        'usage': {'prompt_tokens': 1, 'completion_tokens': 2}
      });
      final u = UsageParser.parseBody(body);
      expect(u.promptTokens, 1);
      expect(u.completionTokens, 2);
    });

    test('SSE 多 data 行取最后 usage', () {
      const body = 'data: {"choices":[{"delta":{"content":"a"}}]}\n\n'
          'data: {"usage":{"prompt_tokens":8,"completion_tokens":8}}\n\n'
          'data: [DONE]\n\n';
      final u = UsageParser.parseBody(body);
      expect(u.promptTokens, 8);
      expect(u.completionTokens, 8);
    });

    test('空响应返回 empty', () {
      expect(UsageParser.parseBody('').isEmpty, isTrue);
    });
  });

  group('extractModel', () {
    test('OpenAI model', () {
      expect(UsageParser.extractModel({'model': 'gpt-4o'}), 'gpt-4o');
    });
    test('Google models/ 前缀被剥离', () {
      expect(UsageParser.extractModel({'model': 'models/gemini-pro'}), 'gemini-pro');
    });
  });

  group('estimateTokens', () {
    test('CJK 估算多于纯英文', () {
      final cjk = UsageParser.estimateTokens('你好世界你好世界你好世界');
      final en = UsageParser.estimateTokens('hello world hello world');
      expect(cjk, greaterThan(en));
    });
  });

  group('RequestPayload.parse', () {
    test('解析 model 与 stream', () {
      final body = utf8.encode(jsonEncode({
        'model': 'gpt-4o',
        'stream': true,
        'messages': [{'role': 'user', 'content': 'hi'}],
      }));
      final p = RequestPayload.parse(body);
      expect(p.model, 'gpt-4o');
      expect(p.stream, isTrue);
      expect(p.estimatedTokens, greaterThan(0));
    });

    test('非 JSON 安全降级', () {
      final p = RequestPayload.parse(utf8.encode('not json at all'));
      expect(p.model, '');
    });
  });
}
