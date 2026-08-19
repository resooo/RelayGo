/// 全局常量配置
class Constants {
  // 代理服务器
  static const int defaultPort = 8788;
  // 默认监听所有网卡，便于局域网内第三方应用访问中转站；
  // 如需仅本机访问，可在设置中改为 127.0.0.1
  static const String defaultHost = '0.0.0.0';
  static const int maxConcurrentConnections = 50; // 同时转发上游的上限
  static const int maxQueuedConnections = 200; // 排队上限，超过直接 429
  static const int maxFailureThreshold = 3; // 连续失败 N 次标记为不可用
  static const int cooldownSeconds = 300; // 冷却 5 分钟后重试（秒）
  static const int upstreamTimeoutSeconds = 120; // 上游响应超时
  static const int upstreamIdleTimeoutSeconds = 30; // 响应体读取空闲超时（防止上游挂起拖死客户端）
  static const int maxRetryKeys = 3; // 单次请求最多尝试的 key 数（自动切换）
  static const int maxRequestBodyBytes = 32 * 1024 * 1024; // 请求体上限 32MB
  static const int usageCaptureBytes = 256 * 1024; // 用于解析 token 用量的采样上限

  // 应用信息
  static const String appName = 'RelayGo';
  static const String appSlogan = 'Your AI Relay, Ready to Go';
  static const String appDescription = 'Mobile AI API Relay & Key Manager';
  static const String appVersion = '1.0.1';
  static const int appBuildNumber = 1;

  // 在线更新
  // 方案一（推荐）：GitHub Releases + 应用内检查。配置 `updateGithubRepo`
  // （格式 owner/repo）后，走 GitHub Releases API，发布 Release 即发版；
  // 若未配置仓库，则回退到下面的静态 JSON 清单（可托管在任意 HTTP 服务/对象存储）。
  static const String updateGithubApiBase = 'https://api.github.com/repos';
  static const String updateGithubApiAccept = 'application/vnd.github+json';
  static const String updateGithubApiLatest = '/releases/latest';
  static const String updateGithubApiList = '/releases?per_page=10';

  /// 关联发布仓库（owner/repo），默认值供 UserSettings 使用；
  /// 为空串时回退到 `defaultUpdateFeedUrl` 的静态清单。
  static const String defaultUpdateGithubRepo = 'resooo/RelayGo';
  static const String defaultUpdateFeedUrl =
      'https://raw.githubusercontent.com/relaygo-mobile/release/main/latest.json';
  static const String defaultUpdateChannel = 'stable';
  static const List<String> updateChannels = ['stable', 'beta'];
  static const int updateCheckTimeoutSeconds = 15;
  static const int updateDownloadTimeoutSeconds = 600;
  static const int updatePeriodicCheckHours = 24; // 定期后台检查间隔（小时）

  // Hive 存储盒
  static const String vaultBox = 'vault'; // 主密钥等敏感信息
  static const String keysBox = 'api_keys';
  static const String logsBox = 'request_logs';
  static const String settingsBox = 'settings';
  static const String rulesBox = 'routing_rules';
  static const String alertsBox = 'alerts';
  static const String providersBox = 'providers'; // 用户自定义提供商

  // 主密钥在 vault 盒中的键名
  static const String masterKeyName = 'master_aes_key';

  // 健康检查接口路径
  static const List<String> healthPaths = ['/health', '/healthz', '/ping'];

  // 中转站自身的管理接口
  static const String statsPath = '/relay/stats';
  static const String versionPath = '/relay/version'; // 当前版本信息
  static const String updateCheckPath = '/relay/update/check'; // 触发在线更新检查
  static const String reportPath = '/relay/report'; // 统计报表（JSON）
  static const String cacheStatsPath = '/relay/cache'; // 缓存统计（DELETE 可清空）

  /// 中转站管理接口集合（这些路径不转发到上游）
  static const List<String> adminPaths = [
    statsPath,
    versionPath,
    updateCheckPath,
    reportPath,
    cacheStatsPath,
  ];

  // 模型列表同步（REQ-003）
  static const String modelsPath = '/v1/models'; // 代理层对外暴露的聚合模型列表（AI 应用查询用）
  static const String modelsBox = 'models';
  static const String syncHistoryBox = 'sync_history';

  // —— 免费 API 推荐（Free LLM API Hub）——
  static const String freeApiFeedUrl =
      'https://raw.githubusercontent.com/pacocartones/free-llm-api-hub/v2.9.0/data/providers.json';
  static const String freeApiBox = 'free_api_cache'; // 本地缓存盒
  static const String freeApiCacheKey = 'providers'; // 缓存数据键
  static const String freeApiCacheTimeKey = 'cached_at'; // 缓存时间戳键
  static const int freeApiRefreshHours = 24; // 超过 24 小时自动刷新
  static const int freeApiFetchTimeoutSeconds = 15;
  static const String freeApiSourceName = 'Free LLM API Hub';
  static const String freeApiVersion = '2.9.0';

  // 客户端可用来强制指定提供商 / key 的请求头
  static const String providerHeader = 'x-relay-provider';
  static const String keyNameHeader = 'x-relay-key';

  // 支持的负载均衡策略
  static const List<String> loadBalanceStrategies = [
    'round_robin',
    'weighted_round_robin',
    'priority',
    'least_connections',
    'response_time',
    'smart',
  ];

  // 日志管理默认值
  static const int defaultLogRetentionDays = 7;
  static const int defaultMaxLogEntries = 5000;
  static const int logFlushMillis = 400; // 批量落盘间隔
  static const int logMemoryCap = 500; // 内存中保留的最近日志条数

  // 额度监控默认值
  static const double defaultQuotaWarnThreshold = 0.9; // 达到 90% 触发告警
  static const int alertsCap = 200; // 告警保留条数

  // —— Phase 3：响应缓存（需求 2.2.4）——
  static const int defaultCacheTtlSeconds = 300; // 默认 5 分钟
  static const int defaultCacheMaxEntries = 500;
  static const int cacheMaxBodyBytes = 1024 * 1024; // 单条响应最大缓存 1MB
  static const String cacheHitHeader = 'x-relay-cache'; // HIT / MISS

  // —— Phase 3：高级限流（需求 2.2.6）——
  static const int defaultIpRateLimitPerMinute = 0; // 0 = 不限制
  static const int defaultGlobalRpmLimit = 0; // 0 = 不限制
  static const int defaultTokenRateLimitPerMinute = 0; // 0 = 不限制
  static const double defaultBurstMultiplier = 1.5; // 令牌桶突发容量倍数
  static const String retryAfterHeader = 'retry-after';

  // —— TPM 自适应挡板 + 429 等待重试（消除上游限流中断）——
  /// 自适应 TPM 挡板默认开启：结合本地用量与上游 429 反馈，把「学到」的
  /// 每 key+模型 token 上限压到实际可用值附近，从源头减少 TPM 限流。
  static const bool defaultAdaptiveTpmEnabled = true;

  /// 乘性减：遇到上游 429 时，把当次用量视为上限并下调到其 < 1 的比例，
  /// 为挡板留出余量，避免同一窗口再次撞限。
  static const double tpmAimdDown = 0.85;

  /// 加性增：一段时间无 429 后，试探性上调，逐步贴近真实上限。
  static const double tpmAimdUp = 0.02;

  /// 429（可恢复 TPM 限流）单次请求最多等待窗口刷新的时长（毫秒）。
  /// 超过预算转为返回 429 + Retry-After，让客户端排队重试而非硬断 503。
  static const int tpmWaitBudgetMs = 8000;

  /// 识别「可恢复 TPM 限流」的错误体关键词（命中才等待重试同 key）。
  static const List<String> tpmRecoverableKeywords = [
    'tokens_per_minute',
    'tpm',
    'inference_tpm',
    'tokens per minute',
    'rate_limit_reached',
    'rate limit reached',
    'requests_limit_reached',
    'context_length_exceeded too_many_requests',
    'too_many_requests',
  ];

  // —— 上游错误智能识别（无感切换 key，避免中断用户）——
  /// 表示「该 key 的免费/可用额度已耗尽」的错误体关键词。
  ///
  /// 命中后切断当前 key 并自动切换下一个可用 key；若候选全部命中，
  /// 则汇总为「所有 key 均无可用量」的友好提示而非透传原始错误。
  /// 覆盖 OpenAI（insufficient_quota / FREE_QUOTA_EXHAUSTED）、Anthropic
  /// （billing_not_active / credit_balance_too_low / insufficient_credit）、
  /// Google（daily quota）以及各类第三方网关。
  static const List<String> quotaExhaustedKeywords = [
    'free_quota_exhausted',
    'free quota',
    'insufficient_quota',
    'insufficient ledger balance',
    'exceeded your current quota',
    'exceeded_current_quota_error',
    'current quota',
    'quota_exceeded',
    'quota exhausted',
    'billing_not_active',
    'billing not active',
    'billing hard limit has been reached',
    'billing_hard_limit',
    'credit_balance_too_low',
    'insufficient_credit',
    'insufficient credit',
    'credit_balance',
    'out of credits',
    'not enough credit',
    'payment_required',
    'account_deactivated',
    'deactivated',
    'usage cap',
    'daily usage limit',
    'daily limit reached',
    'access_terminated',
    'no active billing',
  ];

  /// 表示「鉴权 Key 无效」的错误体关键词（401）。
  static const List<String> authFailedKeywords = [
    'invalid api key',
    'invalid_api_key',
    'authentication failed',
    'unauthorized',
    'incorrect api key',
    'bad credentials',
    'no api key provided',
    'missing api key',
  ];

  /// 标记为「额度耗尽」后，对该 key 的冷却时长（毫秒）。
  ///
  /// 冷却期间后续请求自动跳过该 key（避免反复命中一个已耗尽的 key 拖慢
  /// 其他可用 key），冷却结束后由 [KeyManager] 自动恢复为 active。
  static const int quotaExhaustedCooldownMs = 30 * 60 * 1000; // 30 分钟

  // —— Phase 3：统计报表 ——
  static const int reportMaxDays = 90; // 报表最长回溯天数
}
