/// Key 有效性测试结果状态
///
/// 与 [ApiKey.testResult] 序列化的字符串取值保持一致：
/// `valid` / `invalid` / `timeout` / `error`。
enum KeyTestStatus { valid, invalid, timeout, error }

extension KeyTestStatusX on KeyTestStatus {
  String get name => toString().split('.').last;

  static KeyTestStatus? fromString(String? value) {
    switch (value) {
      case 'valid':
        return KeyTestStatus.valid;
      case 'invalid':
        return KeyTestStatus.invalid;
      case 'timeout':
        return KeyTestStatus.timeout;
      case 'error':
        return KeyTestStatus.error;
      default:
        return null;
    }
  }

  /// 中文标签（需求 2.3.3 状态标识）
  String get label {
    switch (this) {
      case KeyTestStatus.valid:
        return '有效';
      case KeyTestStatus.invalid:
        return '无效';
      case KeyTestStatus.timeout:
        return '超时';
      case KeyTestStatus.error:
        return '异常';
    }
  }

  /// 对应徽标 / 文字颜色
  int get colorValue {
    switch (this) {
      case KeyTestStatus.valid:
        return 0xFF2E7D32; // 绿
      case KeyTestStatus.invalid:
        return 0xFFC62828; // 红
      case KeyTestStatus.timeout:
        return 0xFFF9A825; // 黄
      case KeyTestStatus.error:
        return 0xFFEF6C00; // 橙
    }
  }
}

/// 单次 Key 连通性测试结果
class KeyTestOutcome {
  final KeyTestStatus status;
  final String? error; // 失败原因，如 "401 Unauthorized"
  final int? httpStatus; // 上游 HTTP 状态码（无网络/超时则为 null）
  final Duration elapsed;

  const KeyTestOutcome({
    required this.status,
    this.error,
    this.httpStatus,
    this.elapsed = Duration.zero,
  });

  bool get ok => status == KeyTestStatus.valid;

  /// 有效
  factory KeyTestOutcome.valid([Duration elapsed = Duration.zero]) =>
      KeyTestOutcome(status: KeyTestStatus.valid, elapsed: elapsed);

  /// 无效（上游返回非 2xx）
  factory KeyTestOutcome.invalid(int httpStatus, String reason,
      [Duration elapsed = Duration.zero]) {
    final phrase = _reasonPhrase(httpStatus);
    return KeyTestOutcome(
      status: KeyTestStatus.invalid,
      httpStatus: httpStatus,
      error: phrase == null ? '$httpStatus' : '$httpStatus $phrase',
      elapsed: elapsed,
    );
  }

  /// 超时（含重试后仍超时）
  factory KeyTestOutcome.timeout([String? message]) =>
      KeyTestOutcome(status: KeyTestStatus.timeout, error: message ?? '请求超时');

  /// 其它异常（网络不可达、DNS 失败、证书错误等）
  factory KeyTestOutcome.failure(String message) =>
      KeyTestOutcome(status: KeyTestStatus.error, error: message);

  static String? _reasonPhrase(int status) {
    switch (status) {
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 429:
        return 'Too Many Requests';
      case 500:
        return 'Internal Server Error';
      case 502:
        return 'Bad Gateway';
      case 503:
        return 'Service Unavailable';
      default:
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'error': error,
        'http_status': httpStatus,
        'elapsed_ms': elapsed.inMilliseconds,
      };
}

/// 单条 Key 的测试记录（用于结果汇总与导出）
class KeyTestRecord {
  final String id;
  final String provider;
  final String name;
  final String note;
  final String maskedKey;
  final KeyTestOutcome outcome;

  KeyTestRecord({
    required this.id,
    required this.provider,
    required this.name,
    required this.note,
    required this.maskedKey,
    required this.outcome,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider,
        'name': name,
        'note': note,
        'masked_key': maskedKey,
        'result': outcome.toJson(),
      };
}

/// 批量测试汇总
class BatchTestSummary {
  final List<KeyTestRecord> records;

  const BatchTestSummary(this.records);

  int get total => records.length;
  int get validCount => records.where((r) => r.outcome.ok).length;
  int get invalidCount =>
      records.where((r) => r.outcome.status == KeyTestStatus.invalid).length;
  int get timeoutCount =>
      records.where((r) => r.outcome.status == KeyTestStatus.timeout).length;
  int get errorCount =>
      records.where((r) => r.outcome.status == KeyTestStatus.error).length;

  /// 所有「未通过」的 key（无效 + 超时 + 异常），用于一键禁用 / 删除
  List<KeyTestRecord> get failed =>
      records.where((r) => !r.outcome.ok).toList();

  /// 导出为纯文本汇总（需求 2.2.4）
  String toText() {
    final buf = StringBuffer();
    buf.writeln('测试完成！');
    buf.writeln('✅ 有效：$validCount 个');
    buf.writeln('❌ 无效：$invalidCount 个');
    buf.writeln('⚠️ 超时：$timeoutCount 个');
    if (errorCount > 0) buf.writeln('⚠️ 异常：$errorCount 个');
    if (failed.isNotEmpty) {
      buf.writeln('');
      buf.writeln('无效 / 失败 Key 列表：');
      for (var i = 0; i < failed.length; i++) {
        final r = failed[i];
        buf.writeln('${i + 1}. ${r.provider} - ${r.maskedKey}'
            '${r.note.isNotEmpty ? '（${r.note}）' : ''}');
        buf.writeln('   原因：${r.outcome.error ?? r.outcome.status.label}');
      }
    }
    return buf.toString();
  }

  /// 导出为 CSV（含表头）
  String toCsv() {
    final buf = StringBuffer();
    buf.writeln('provider,name,note,masked_key,status,http_status,error');
    for (final r in records) {
      String esc(String s) => '"${s.replaceAll('"', '""')}"';
      buf.writeln([
        esc(r.provider),
        esc(r.name),
        esc(r.note),
        esc(r.maskedKey),
        r.outcome.status.name,
        r.outcome.httpStatus?.toString() ?? '',
        esc(r.outcome.error ?? ''),
      ].join(','));
    }
    return buf.toString();
  }
}
