import 'package:relaygo/config/constants.dart';
import 'package:relaygo/services/rate_limiter.dart';

/// 上游错误的类型，用于决定「是否值得无感切换 key / 等待重试 / 直接透传」。
///
/// 设计目标（需求：让用户感觉不到上游错误的存在）：
///  - [quotaExhausted] / [rateLimited] / [serverError] / [modelNotFound] /
///    [authFailed] / [permissionDenied] 都视为「换一个 key 可能就成功」的
///    上游侧问题，代理会**无感**切换到下一个候选 key 重试；
///  - [badRequest] / [unknown] 属于请求本身或无法归类的问题，切换 key 无济于事，
///    仅在确认所有候选均不可用时才向用户透传友好提示。
class UpstreamErrorClassifier {
  const UpstreamErrorClassifier._();

  /// 分类上游错误。
  ///
  /// [statusCode] 为上游 HTTP 状态码，[body] 为已捕获的错误响应体（可能为空）。
  /// 判定优先级：先在响应体里搜「额度耗尽」关键词（很多厂商用 400/403 表达
  /// quota/billing），再按状态码分派。
  static UpstreamErrorKind classify(int statusCode, String body) {
    final b = body.toLowerCase();

    // 1) 额度/计费耗尽优先于状态码判断（OpenAI 400、Anthropic 403、Azure 429 等）
    if (_containsAny(b, Constants.quotaExhaustedKeywords)) {
      return UpstreamErrorKind.quotaExhausted;
    }

    // 2) 429：限流。TPM/RPM/并发/资源耗尽等，只要换 key 有机会成功即可重试。
    if (statusCode == 429) {
      return UpstreamErrorKind.rateLimited;
    }

    // 3) 401：鉴权失败（key 失效）。
    if (statusCode == 401 || _containsAny(b, Constants.authFailedKeywords)) {
      return UpstreamErrorKind.authFailed;
    }

    // 4) 404：模型不存在 / 资源未找到，换 key 可能命中含此模型的其他 key。
    if (statusCode == 404) {
      return UpstreamErrorKind.modelNotFound;
    }

    // 5) 5xx：上游服务异常，换 key 重试通常是安全的。
    if (statusCode >= 500) {
      return UpstreamErrorKind.serverError;
    }

    // 6) 403：权限拒绝（非配额/计费类）。可能有 key 的权限差异，尝试切换。
    if (statusCode == 403) {
      return UpstreamErrorKind.permissionDenied;
    }

    // 7) 4xx 请求问题：切换 key 不会改变结果，视为不可恢复。
    if (statusCode >= 400 && statusCode < 500) {
      return UpstreamErrorKind.badRequest;
    }

    return UpstreamErrorKind.unknown;
  }

  /// 该错误是否应由代理「无感切换到下一个 key」重试。
  ///
  /// 当上游问题源于【key / 上游服务 / 额度】而与【本次请求内容】无关时，
  /// 换一个 key 就可能成功，因此值得静默重试。
  static bool isSilentlyRetryable(UpstreamErrorKind kind) {
    switch (kind) {
      case UpstreamErrorKind.quotaExhausted:
      case UpstreamErrorKind.rateLimited:
      case UpstreamErrorKind.serverError:
      case UpstreamErrorKind.modelNotFound:
      case UpstreamErrorKind.authFailed:
      case UpstreamErrorKind.permissionDenied:
        return true;
      case UpstreamErrorKind.badRequest:
      case UpstreamErrorKind.unknown:
        return false;
    }
  }

  /// 是否为「可等待同一 TPM 窗口刷新后重试同 key」的限流。
  /// 复用了限流器里针对 TPM 关键词的预判。
  static bool isRecoverableTpm(int statusCode, String body) =>
      RateLimiter.isRecoverableTpmLimit(statusCode, body);

  static bool _containsAny(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }
}

/// 上游错误的分类结果。
enum UpstreamErrorKind {
  /// 额度/免费额度/计费耗尽（换 key 有望成功）
  quotaExhausted,

  /// 限流（429，含 TPM/RPM/资源耗尽）
  rateLimited,

  /// 鉴权失败（401，key 无效）
  authFailed,

  /// 模型或资源不存在（404）
  modelNotFound,

  /// 权限拒绝（403，非计费类）
  permissionDenied,

  /// 上游服务异常（5xx）
  serverError,

  /// 请求内容问题（400 等，切换 key 无效）
  badRequest,

  /// 无法识别
  unknown,
}
