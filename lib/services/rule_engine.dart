import 'package:relaygo/models/routing_rule.dart';
import 'package:relaygo/services/providers/base_provider.dart'; // ProxyRequest

/// 规则引擎（需求 2.2.3）
///
/// 根据请求上下文（模型名、大小、时间段、来源 IP、Token 数、成本预算等）
/// 智能路由到指定提供商 / 策略 / key 组，或拦截请求。
///
/// 条件表达式示例：
///   request.model contains 'gpt-4'
///   request.model in ['gpt-4', 'gpt-4o']
///   request.size > 8192 && request.tokens < 4000
///   request.hour in ['00:00-06:00']        # 仅凌晨时段命中（hour 为 0-23 整数）
///   request.ip matches '^10\\.'            # IP 正则
///   request.provider == 'openai' || request.tokens >= 8000
///
/// 动作表达式示例：
///   use_provider('openai')
///   use_provider('anthropic', strategy='priority', group='free')
///   block('该时段禁用')
class RuleEngine {
  List<RoutingRule> rules;

  RuleEngine({this.rules = const []});

  /// 规则变更后由调用方刷新（代理服务器持有同一实例）
  setRules(List<RoutingRule> value) => rules = value;

  /// 从 ProxyRequest 构建求值上下文（供表达式中的 request.* 访问）
  static Map<String, dynamic> buildContext(ProxyRequest request) {
    final now = DateTime.now();
    return {
      'request': {
        'model': request.model,
        'provider': '',
        'size': request.bodyBytes,
        'tokens': request.body.isEmpty
            ? 0
            : _estimateTokensQuick(String.fromCharCodes(
                request.body.length > 4096
                    ? request.body.sublist(0, 4096)
                    : request.body)),
        'ip': request.clientIp,
        'path': request.path,
        'method': request.method,
        'hour': now.hour,
        'time': '${_pad(now.hour)}:${_pad(now.minute)}',
        'date': '${now.year}-${_pad(now.month)}-${_pad(now.day)}',
        'budget': 0,
      },
      'true': true,
      'false': false,
    };
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');

  static int _estimateTokensQuick(String text) {
    if (text.isEmpty) return 0;
    var cjk = 0;
    for (final code in text.runes) {
      if (code >= 0x4E00 && code <= 0x9FFF) cjk++;
    }
    return (cjk * 0.7 + (text.length - cjk) / 4).ceil();
  }

  /// 评估规则，返回第一条命中规则产生的路由决策；无命中返回 null。
  ///
  /// [context] 通常来自 [buildContext]，也可由调用方注入（如补充 request.provider）。
  RoutingDecision? evaluate(Map<String, dynamic> context) {
    final sorted = [...rules];
    sorted.sort((a, b) => a.order.compareTo(b.order));
    for (final rule in sorted) {
      if (!rule.enabled || rule.condition.trim().isEmpty) continue;
      RoutingDecision? decision;
      try {
        final expr = _RuleParser(rule.condition).parseOr();
        if (expr.eval(context) == true) {
          decision = _parseAction(rule.action);
          decision.ruleName = rule.name;
          return decision;
        }
      } catch (_) {
        // 规则表达式残缺：跳过，不阻断其余请求
        continue;
      }
    }
    return null;
  }

  /// 校验条件表达式语法（供 UI 实时提示），返回 null 表示通过，否则返回错误说明。
  String? validateCondition(String expr) {
    try {
      final node = _RuleParser(expr).parseOr();
      // 尝试空上下文求值，仅检查运行时类型错误（变量缺失不视为语法错误）
      node.eval({'request': <String, dynamic>{}, 'true': true, 'false': false});
      return null;
    } on _RuleParseError catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// 解析动作表达式
  RoutingDecision _parseAction(String action) {
    final tokens = _ActionTokenizer(action).tokenize();
    final parser = _ActionParser(tokens);
    return parser.parse();
  }
}

/// 路由决策：规则命中后，代理服务器据此调整转发目标。
class RoutingDecision {
  final String? provider; // 覆盖自动识别的提供商；null 表示沿用识别结果
  final String? strategy; // 负载均衡策略
  final String? group; // 仅使用属于该组的 key
  final bool block; // 是否拦截请求
  final String? blockReason;
  String? ruleName; // 命中的规则名（便于日志展示）

  RoutingDecision({
    this.provider,
    this.strategy,
    this.group,
    this.block = false,
    this.blockReason,
    this.ruleName,
  });

  @override
  String toString() =>
      'RoutingDecision(provider: $provider, strategy: $strategy, '
      'group: $group, block: $block, ruleName: $ruleName)';
}

// ————————————————————————————————————————————————————————————
// 条件表达式：词法 / 语法 / 求值
// ————————————————————————————————————————————————————————————

class _RuleParseError implements Exception {
  final String message;
  _RuleParseError(this.message);
}

enum _Tok {
  ident,
  num,
  str,
  op,
  lparen,
  rparen,
  comma,
  lbracket,
  rbracket,
  dot,
  eof,
}

class _Token {
  final _Tok type;
  final String value;
  _Token(this.type, this.value);
}

class _RuleTokenizer {
  final String src;
  int pos = 0;
  _RuleTokenizer(this.src);

  List<_Token> tokenize() {
    final out = <_Token>[];
    while (pos < src.length) {
      final c = src[pos];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        pos++;
        continue;
      }
      if (c == '(') {
        out.add(_Token(_Tok.lparen, c));
        pos++;
      } else if (c == ')') {
        out.add(_Token(_Tok.rparen, c));
        pos++;
      } else if (c == '[') {
        out.add(_Token(_Tok.lbracket, c));
        pos++;
      } else if (c == ']') {
        out.add(_Token(_Tok.rbracket, c));
        pos++;
      } else if (c == ',') {
        out.add(_Token(_Tok.comma, c));
        pos++;
      } else if (c == '.') {
        out.add(_Token(_Tok.dot, c));
        pos++;
      } else if (c == '"' || c == "'") {
        out.add(_Token(_Tok.str, _readString(c)));
      } else if (_isDigit(c) || (c == '-' && _isDigit(_peek()))) {
        out.add(_Token(_Tok.num, _readNumber()));
      } else if (_isIdentStart(c)) {
        out.add(_Token(_Tok.ident, _readIdent()));
      } else if ('+-*/!=<>&|'.contains(c)) {
        out.add(_Token(_Tok.op, _readOp()));
      } else {
        throw _RuleParseError('无法识别的字符：$c');
      }
    }
    out.add(_Token(_Tok.eof, ''));
    return out;
  }

  bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
  bool _isIdentStart(String c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
      c == '_';
  bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);
  String _peek() => pos + 1 < src.length ? src[pos + 1] : '';

  String _readString(String quote) {
    pos++; // 跳过起始引号
    final buf = StringBuffer();
    while (pos < src.length) {
      final c = src[pos];
      if (c == '\\') {
        pos++;
        if (pos < src.length) buf.write(src[pos]);
        pos++;
        continue;
      }
      if (c == quote) {
        pos++;
        return buf.toString();
      }
      buf.write(c);
      pos++;
    }
    throw _RuleParseError('字符串未闭合');
  }

  String _readNumber() {
    final start = pos;
    if (src[pos] == '-') pos++;
    while (pos < src.length && (_isDigit(src[pos]) || src[pos] == '.')) {
      pos++;
    }
    return src.substring(start, pos);
  }

  String _readIdent() {
    final start = pos;
    while (pos < src.length && _isIdentPart(src[pos])) {
      pos++;
    }
    return src.substring(start, pos);
  }

  String _readOp() {
    final c = src[pos];
    if (c == '&') {
      if (_peek() == '&') {
        pos += 2;
        return '&&';
      }
      pos++;
      return '&';
    }
    if (c == '|') {
      if (_peek() == '|') {
        pos += 2;
        return '||';
      }
      pos++;
      return '|';
    }
    if (c == '!') {
      if (_peek() == '=') {
        pos += 2;
        return '!=';
      }
      pos++;
      return '!';
    }
    if (c == '=') {
      if (_peek() == '=') {
        pos += 2;
        return '==';
      }
      pos++;
      return '=';
    }
    if (c == '>') {
      if (_peek() == '=') {
        pos += 2;
        return '>=';
      }
      pos++;
      return '>';
    }
    if (c == '<') {
      if (_peek() == '=') {
        pos += 2;
        return '<=';
      }
      pos++;
      return '<';
    }
    pos++;
    return c;
  }
}

/// 表达式 AST 节点
abstract class _Expr {
  dynamic eval(Map<String, dynamic> ctx);
}

class _BoolLit extends _Expr {
  final bool value;
  _BoolLit(this.value);
  @override
  dynamic eval(_) => value;
}

class _NumLit extends _Expr {
  final num value;
  _NumLit(this.value);
  @override
  dynamic eval(_) => value;
}

class _StrLit extends _Expr {
  final String value;
  _StrLit(this.value);
  @override
  dynamic eval(_) => value;
}

class _NullLit extends _Expr {
  @override
  dynamic eval(_) => null;
}

class _Path extends _Expr {
  final List<String> parts;
  _Path(this.parts);
  @override
  dynamic eval(Map<String, dynamic> ctx) {
    dynamic cur = ctx;
    for (final p in parts) {
      if (cur is Map && cur.containsKey(p)) {
        cur = cur[p];
      } else {
        return null;
      }
    }
    return cur;
  }
}

class _Call extends _Expr {
  final String name;
  final List<_Expr> args;
  _Call(this.name, this.args);
  @override
  dynamic eval(Map<String, dynamic> ctx) {
    final values = args.map((a) => a.eval(ctx)).toList();
    return _builtin(name, values);
  }
}

class _Unary extends _Expr {
  final String op;
  final _Expr operand;
  _Unary(this.op, this.operand);
  @override
  dynamic eval(Map<String, dynamic> ctx) {
    final v = operand.eval(ctx);
    if (op == '!') return !_truthy(v);
    if (op == '-') return (v is num) ? -v : null;
    return v;
  }
}

class _Binary extends _Expr {
  final String op;
  final _Expr left;
  final _Expr right;
  _Binary(this.op, this.left, this.right);
  @override
  dynamic eval(Map<String, dynamic> ctx) {
    final l = left.eval(ctx);
    final r = right.eval(ctx);
    switch (op) {
      case '==':
        return _equals(l, r);
      case '!=':
        return !_equals(l, r);
      case '>':
        return _compare(l, r) > 0;
      case '>=':
        return _compare(l, r) >= 0;
      case '<':
        return _compare(l, r) < 0;
      case '<=':
        return _compare(l, r) <= 0;
      case '&&':
        return _truthy(l) && _truthy(r);
      case '||':
        return _truthy(l) || _truthy(r);
      case 'in':
        return _membership(l, r);
      case 'contains':
      case 'starts_with':
      case 'startsWith':
      case 'ends_with':
      case 'endsWith':
      case 'matches':
        return _builtin(op, [l, r]);
      default:
        throw _RuleParseError('未知运算符：$op');
    }
  }
}

class _RuleParser {
  final List<_Token> tokens;
  int i = 0;
  _RuleParser(String src) : tokens = _RuleTokenizer(src).tokenize();

  _Token get _cur => tokens[i];
  void _advance() => i++;

  _Expr parseOr() {
    var left = parseAnd();
    while (_cur.type == _Tok.op && (_cur.value == '||') ||
        _cur.type == _Tok.ident && _cur.value == 'or') {
      _advance();
      final right = parseAnd();
      left = _Binary('||', left, right);
    }
    return left;
  }

  _Expr parseAnd() {
    var left = parseNot();
    while (_cur.type == _Tok.op && (_cur.value == '&&') ||
        _cur.type == _Tok.ident && _cur.value == 'and') {
      _advance();
      final right = parseNot();
      left = _Binary('&&', left, right);
    }
    return left;
  }

  _Expr parseNot() {
    if (_cur.type == _Tok.op && _cur.value == '!' ||
        _cur.type == _Tok.ident && _cur.value == 'not') {
      _advance();
      return _Unary('!', parseNot());
    }
    return parseComparison();
  }

  _Expr parseComparison() {
    final left = parseAdd();
    if (_cur.type == _Tok.op &&
        ['==', '!=', '>', '>=', '<', '<='].contains(_cur.value)) {
      final op = _cur.value;
      _advance();
      final right = parseAdd();
      return _Binary(op, left, right);
    }
    if (_cur.type == _Tok.ident && _cur.value == 'in') {
      _advance();
      final right = parseAdd();
      return _Binary('in', left, right);
    }
    // 中缀方法运算符：a contains b / a matches b / a starts_with b / a ends_with b
    if (_cur.type == _Tok.ident &&
        const [
          'contains',
          'starts_with',
          'startsWith',
          'ends_with',
          'endsWith',
          'matches',
        ].contains(_cur.value)) {
      final op = _cur.value;
      _advance();
      final right = parseAdd();
      return _Binary(op, left, right);
    }
    return left;
  }

  _Expr parseAdd() {
    var left = parseMul();
    while (_cur.type == _Tok.op && (_cur.value == '+' || _cur.value == '-')) {
      final op = _cur.value;
      _advance();
      left = _Binary(op, left, parseMul());
    }
    return left;
  }

  _Expr parseMul() {
    var left = parseUnary();
    while (_cur.type == _Tok.op && (_cur.value == '*' || _cur.value == '/')) {
      final op = _cur.value;
      _advance();
      left = _Binary(op, left, parseUnary());
    }
    return left;
  }

  _Expr parseUnary() {
    if (_cur.type == _Tok.op && _cur.value == '-') {
      _advance();
      return _Unary('-', parseUnary());
    }
    return parsePrimary();
  }

  _Expr parsePrimary() {
    final t = _cur;
    if (t.type == _Tok.lparen) {
      _advance();
      final e = parseOr();
      if (_cur.type != _Tok.rparen) throw _RuleParseError('缺少右括号');
      _advance();
      return e;
    }
    if (t.type == _Tok.num) {
      _advance();
      final n = num.tryParse(t.value);
      if (n == null) throw _RuleParseError('非法数字：${t.value}');
      return _NumLit(n);
    }
    if (t.type == _Tok.str) {
      _advance();
      return _StrLit(t.value);
    }
    if (t.type == _Tok.ident) {
      if (t.value == 'true') {
        _advance();
        return _BoolLit(true);
      }
      if (t.value == 'false') {
        _advance();
        return _BoolLit(false);
      }
      if (t.value == 'null') {
        _advance();
        return _NullLit();
      }
      // 函数调用？
      if (i + 1 < tokens.length && tokens[i + 1].type == _Tok.lparen) {
        _advance();
        final args = <_Expr>[];
        _advance(); // 跳过 (
        if (_cur.type != _Tok.rparen) {
          args.add(parseOr());
          while (_cur.type == _Tok.comma) {
            _advance();
            args.add(parseOr());
          }
        }
        if (_cur.type != _Tok.rparen) throw _RuleParseError('函数缺少右括号');
        _advance();
        return _Call(t.value, args);
      }
      // 路径：ident(.ident)*
      final parts = <String>[t.value];
      _advance();
      while (_cur.type == _Tok.dot) {
        _advance();
        if (_cur.type != _Tok.ident) throw _RuleParseError('路径非法');
        parts.add(_cur.value);
        _advance();
      }
      return _Path(parts);
    }
    if (t.type == _Tok.lbracket) {
      return _parseList();
    }
    throw _RuleParseError('意外的符号：${t.value}');
  }

  _Expr _parseList() {
    _advance(); // [
    final items = <_Expr>[];
    if (_cur.type != _Tok.rbracket) {
      items.add(parseOr());
      while (_cur.type == _Tok.comma) {
        _advance();
        items.add(parseOr());
      }
    }
    if (_cur.type != _Tok.rbracket) throw _RuleParseError('列表缺少 ]');
    _advance();
    return _Call('__list', items);
  }
}

// ————————————————————————————————————————————————————————————
// 求值辅助
// ————————————————————————————————————————————————————————————

bool _truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  return true;
}

bool _equals(dynamic l, dynamic r) {
  if (l == null || r == null) return l == r;
  if (l is num && r is num) return l == r;
  if (l is String && r is String) return l == r;
  if (l is bool && r is bool) return l == r;
  return l.toString() == r.toString();
}

int _compare(dynamic l, dynamic r) {
  if (l is num && r is num) return l.compareTo(r);
  if (l is String && r is String) return l.compareTo(r);
  return l.toString().compareTo(r.toString());
}

/// 成员判断：right 为列表，逐元素匹配；支持时段范围字符串 'HH:MM-HH:MM'（按 hour 或 'HH:MM' 比较）。
bool _membership(dynamic left, dynamic right) {
  if (right is! List) return false;
  for (final el in right) {
    if (_equals(left, el)) return true;
    if (el is String && _isTimeRange(el)) {
      if (left is int && _inRangeHour(left, el)) return true;
      if (left is String && _inRangeTime(left, el)) return true;
    }
  }
  return false;
}

bool _isTimeRange(String s) => RegExp(r'^\d{1,2}:\d{2}-\d{1,2}:\d{2}$').hasMatch(s);

bool _inRangeHour(int hour, String range) {
  final parts = range.split('-');
  final start = _hhmmToHour(parts[0]);
  final end = _hhmmToHour(parts[1]);
  if (start <= end) return hour >= start && hour <= end;
  return hour >= start || hour <= end; // 跨午夜
}

bool _inRangeTime(String time, String range) {
  final parts = range.split('-');
  final t = _hhmmToMin(time.split(':').take(2).join(':'));
  final s = _hhmmToMin(parts[0]);
  final e = _hhmmToMin(parts[1]);
  if (s <= e) return t >= s && t <= e;
  return t >= s || t <= e;
}

int _hhmmToHour(String hhmm) {
  final p = hhmm.split(':');
  return int.tryParse(p[0]) ?? 0;
}

int _hhmmToMin(String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p[0]) ?? 0;
  final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
  return h * 60 + m;
}

dynamic _builtin(String name, List<dynamic> args) {
  switch (name) {
    case '__list':
      return args;
    case 'contains':
      if (args.length < 2) return false;
      final a = args[0];
      final b = args[1];
      if (a is String && b is String) return a.contains(b);
      return false;
    case 'starts_with':
    case 'startsWith':
      if (args.length < 2) return false;
      return args[0] is String && args[1] is String
          ? (args[0] as String).startsWith(args[1] as String)
          : false;
    case 'ends_with':
    case 'endsWith':
      if (args.length < 2) return false;
      return args[0] is String && args[1] is String
          ? (args[0] as String).endsWith(args[1] as String)
          : false;
    case 'matches':
      if (args.length < 2) return false;
      try {
        return RegExp(args[1].toString()).hasMatch(args[0]?.toString() ?? '');
      } catch (_) {
        return false;
      }
    case 'length':
      return args.isNotEmpty ? (args[0]?.toString().length ?? 0) : 0;
    case 'lower':
      return args.isNotEmpty ? (args[0]?.toString().toLowerCase() ?? '') : '';
    case 'upper':
      return args.isNotEmpty ? (args[0]?.toString().toUpperCase() ?? '') : '';
    case 'in':
      return _membership(args.isNotEmpty ? args[0] : null,
          args.length > 1 ? args[1] : null);
    default:
      throw _RuleParseError('未知函数：$name');
  }
}

// ————————————————————————————————————————————————————————————
// 动作表达式：词法 / 解析
// ————————————————————————————————————————————————————————————

class _ActionToken {
  final String type; // 'ident' | 'str' | 'num' | 'lparen' | 'rparen' | 'comma' | 'assign'
  final String value;
  _ActionToken(this.type, this.value);
}

class _ActionTokenizer {
  final String src;
  int pos = 0;
  _ActionTokenizer(this.src);

  List<_ActionToken> tokenize() {
    final out = <_ActionToken>[];
    while (pos < src.length) {
      final c = src[pos];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        pos++;
        continue;
      }
      if (c == '(') {
        out.add(_ActionToken('lparen', c));
        pos++;
      } else if (c == ')') {
        out.add(_ActionToken('rparen', c));
        pos++;
      } else if (c == ',') {
        out.add(_ActionToken('comma', c));
        pos++;
      } else if (c == '=') {
        out.add(_ActionToken('assign', c));
        pos++;
      } else if (c == '"' || c == "'") {
        out.add(_ActionToken('str', _readString(c)));
      } else if (_isDigit(c)) {
        out.add(_ActionToken('num', _readNumber()));
      } else if (_isIdentStart(c)) {
        out.add(_ActionToken('ident', _readIdent()));
      } else {
        throw _RuleParseError('动作表达式无法识别的字符：$c');
      }
    }
    return out;
  }

  bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
  bool _isIdentStart(String c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
      c == '_';
  bool _isIdentPart(String c) =>
      _isIdentStart(c) || _isDigit(c) || c == '-';

  String _readString(String quote) {
    pos++;
    final buf = StringBuffer();
    while (pos < src.length) {
      final c = src[pos];
      if (c == '\\') {
        pos++;
        if (pos < src.length) buf.write(src[pos]);
        pos++;
        continue;
      }
      if (c == quote) {
        pos++;
        return buf.toString();
      }
      buf.write(c);
      pos++;
    }
    throw _RuleParseError('动作字符串未闭合');
  }

  String _readNumber() {
    final start = pos;
    while (pos < src.length && (_isDigit(src[pos]) || src[pos] == '.')) {
      pos++;
    }
    return src.substring(start, pos);
  }

  String _readIdent() {
    final start = pos;
    while (pos < src.length && _isIdentPart(src[pos])) {
      pos++;
    }
    return src.substring(start, pos);
  }
}

class _ActionParser {
  final List<_ActionToken> tokens;
  int i = 0;
  _ActionParser(this.tokens);

  RoutingDecision parse() {
    if (tokens.isEmpty || tokens[0].type != 'ident') {
      throw _RuleParseError('动作表达式必须以函数名开头');
    }
    final name = tokens[0].value;
    if (tokens.length < 2 || tokens[1].type != 'lparen') {
      throw _RuleParseError('动作表达式缺少括号');
    }
    i = 2; // 跳过 name + (
    final positional = <String>[];
    final kwargs = <String, String>{};
    if (tokens[i].type != 'rparen') {
      _parseArg(positional, kwargs);
      while (tokens[i].type == 'comma') {
        i++;
        _parseArg(positional, kwargs);
      }
    }
    if (tokens[i].type != 'rparen') throw _RuleParseError('动作缺少右括号');

    if (name == 'use_provider') {
      final provider = positional.isNotEmpty ? positional[0] : kwargs['provider'];
      if (provider == null || provider.isEmpty) {
        throw _RuleParseError('use_provider 缺少提供商参数');
      }
      return RoutingDecision(
        provider: provider,
        strategy: kwargs['strategy'],
        group: kwargs['group'],
      );
    } else if (name == 'use_group') {
      final group = positional.isNotEmpty ? positional[0] : kwargs['group'];
      return RoutingDecision(group: group);
    } else if (name == 'block' || name == 'reject') {
      final reason = positional.isNotEmpty ? positional[0] : kwargs['reason'];
      return RoutingDecision(block: true, blockReason: reason);
    }
    throw _RuleParseError('未知动作：$name');
  }

  void _parseArg(List<String> positional, Map<String, String> kwargs) {
    if (tokens[i].type == 'ident' && i + 1 < tokens.length && tokens[i + 1].type == 'assign') {
      final key = tokens[i].value;
      i += 2;
      final value = _readValue();
      kwargs[key] = value;
      return;
    }
    positional.add(_readValue());
  }

  String _readValue() {
    if (tokens[i].type == 'str' || tokens[i].type == 'num') {
      final v = tokens[i].value;
      i++;
      return v;
    }
    if (tokens[i].type == 'ident') {
      final v = tokens[i].value;
      i++;
      return v;
    }
    throw _RuleParseError('动作参数非法');
  }
}
