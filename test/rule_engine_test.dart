import 'dart:convert';
import 'package:relaygo/models/routing_rule.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/services/rule_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('条件表达式解析与求值', () {
    final ctx = {
      'request': {
        'model': 'gpt-4o-mini',
        'provider': 'openai',
        'size': 2048,
        'tokens': 500,
        'ip': '10.0.0.5',
        'hour': 3,
        'time': '03:30',
        'budget': 0,
      },
      'true': true,
      'false': false,
    };

    test('contains 字符串包含', () {
      final e = RuleEngine().evaluate({
        ...ctx,
        'request': {...ctx['request'] as Map, 'model': 'gpt-4'},
      });
      // 无规则时返回 null
      expect(e, isNull);
    });

    test('命中条件返回路由决策', () {
      final engine = RuleEngine(rules: [
        RoutingRule(
          id: '1',
          name: 'gpt4',
          condition: "request.model contains 'gpt-4'",
          action: "use_provider('openai')",
          enabled: true,
        ),
      ]);
      final decision = engine.evaluate(ctx);
      expect(decision, isNotNull);
      expect(decision!.provider, 'openai');
      expect(decision.ruleName, 'gpt4');
    });

    test('in 列表成员匹配', () {
      final engine = RuleEngine(rules: [
        RoutingRule(
          id: '1',
          name: 'list',
          condition: "request.model in ['gpt-4', 'gpt-4o-mini']",
          action: "use_provider('openai')",
        ),
      ]);
      expect(engine.evaluate(ctx), isNotNull);
    });

    test('数值比较与 && 逻辑', () {
      final engine = RuleEngine(rules: [
        RoutingRule(
          id: '1',
          name: 'big',
          condition: 'request.size > 1024 && request.tokens < 1000',
          action: "use_provider('openai')",
        ),
      ]);
      expect(engine.evaluate(ctx), isNotNull);
    });

    test('时段范围 in [HH:MM-HH:MM]（按 hour）', () {
      final engine = RuleEngine(rules: [
        RoutingRule(
          id: '1',
          name: 'night',
          condition: "request.hour in ['00:00-06:00']",
          action: "use_provider('openai', group='free')",
        ),
      ]);
      final d = engine.evaluate(ctx);
      expect(d, isNotNull);
      expect(d!.group, 'free');
    });

    test('正则 matches', () {
      final engine = RuleEngine(rules: [
        RoutingRule(
          id: '1',
          name: 'ip',
          condition: "request.ip matches '^10\\.'",
          action: "use_provider('openai')",
        ),
      ]);
      expect(engine.evaluate(ctx), isNotNull);
    });

    test('未命中条件返回 null', () {
      final engine = RuleEngine(rules: [
        RoutingRule(
          id: '1',
          name: 'miss',
          condition: "request.model contains 'claude'",
          action: "use_provider('anthropic')",
        ),
      ]);
      expect(engine.evaluate(ctx), isNull);
    });

    test('禁用规则不参与匹配', () {
      final engine = RuleEngine(rules: [
        RoutingRule(
          id: '1',
          name: 'off',
          condition: "request.model contains 'gpt-4'",
          action: "use_provider('openai')",
          enabled: false,
        ),
      ]);
      expect(engine.evaluate(ctx), isNull);
    });

    test('block 动作返回 block 决策', () {
      final engine = RuleEngine(rules: [
        RoutingRule(
          id: '1',
          name: 'deny',
          condition: "request.model contains 'gpt-4'",
          action: "block('禁止 gpt-4')",
        ),
      ]);
      final d = engine.evaluate(ctx);
      expect(d!.block, isTrue);
      expect(d.blockReason, '禁止 gpt-4');
    });
  });

  group('validateCondition 语法校验', () {
    final engine = RuleEngine();
    test('合法表达式返回 null', () {
      expect(engine.validateCondition("request.model contains 'x'"), isNull);
    });
    test('括号不匹配报错', () {
      expect(engine.validateCondition("(request.model == 'x'"), isNotNull);
    });
    test('非法运算符报错', () {
      expect(engine.validateCondition("request.model ~~ 'x'"), isNotNull);
    });
  });

  group('ProxyRequest 构建上下文', () {
    test('buildContext 包含 request.* 字段', () {
      final req = ProxyRequest(
        method: 'POST',
        path: '/v1/chat/completions',
        model: 'gpt-4o',
        body: utf8.encode(
            jsonEncode({'model': 'gpt-4o', 'messages': []})),
      );
      final ctx = RuleEngine.buildContext(req);
      expect(ctx['request']['model'], 'gpt-4o');
      expect(ctx['request']['size'], greaterThan(0));
    });
  });
}
