import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/config/environment.dart';
import 'package:relaygo/config/standard_models.dart';
import 'package:relaygo/models/alert.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/request_log.dart';
import 'package:relaygo/models/user_settings.dart';
import 'package:relaygo/models/app_release.dart';
import 'package:relaygo/services/cache_manager.dart';
import 'package:relaygo/services/key_manager.dart';
import 'package:relaygo/services/load_balancer.dart';
import 'package:relaygo/services/log_service.dart';
import 'package:relaygo/services/model_normalizer.dart';
import 'package:relaygo/database/database_helper.dart';
import 'package:relaygo/database/model_repository.dart';
import 'package:relaygo/services/providers/base_provider.dart';
import 'package:relaygo/services/providers/provider_factory.dart';
import 'package:relaygo/services/quota_monitor.dart';
import 'package:relaygo/services/rate_limiter.dart';
import 'package:relaygo/services/report_service.dart';
import 'package:relaygo/services/rule_engine.dart';
import 'package:relaygo/services/update_service.dart';
import 'package:relaygo/utils/usage_parser.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 单条「提供商 + key」候选
///
/// [actualModel] 非空时表示本次请求来自「能力虚拟模型」，
/// 转发前需把请求体里的模型名改写为该真实模型（避免把 virtualId 透传给上游）。
class _Pair {
  final BaseProvider provider;
  final ApiKey key;
  final String? actualModel;
  _Pair(this.provider, this.key, [this.actualModel]);
}

/// 本地 HTTP 代理服务器（Phase 3）
///
/// 整合：规则引擎路由、多提供商自动切换与失败重试、并发信号量、SSE 透传、
/// token 计费、批量日志、额度监控，以及 Phase 3 的响应缓存、
/// 多维度高级限流与管理接口（版本 / 在线更新检查 / 报表 / 缓存）。
class ProxyServer {
  final KeyManager keyManager;
  final LoadBalancer loadBalancer;
  final LogService logService;
  final RuleEngine ruleEngine;
  final QuotaMonitor quotaMonitor;
  final UserSettings settings;

  /// 响应缓存（需求 2.2.4）
  late final CacheManager cache;

  /// 高级限流（需求 2.2.6）
  late final RateLimiter rateLimiter;

  /// 统计报表（供 /relay/report 接口）
  late final ReportService reportService;

  /// 在线更新（供 /relay/update/check 接口）
  final UpdateService? updateService;

  /// 模型库（供 /v1/models 聚合接口，REQ-003）
  ///
  /// 惰性解析：未显式注入时，直到首次访问才回落到全局 Box，
  /// 避免构造期就强依赖数据库初始化顺序（便于单测与延迟启动）。
  final ModelRepository? _modelRepositoryOverride;
  ModelRepository? _modelRepositoryFallback;

  ModelRepository get modelRepository =>
      _modelRepositoryOverride ??
      (_modelRepositoryFallback ??= ModelRepository(DatabaseHelper.models));

  int port;
  String host;
  String loadBalanceStrategy;

  HttpServer? _server;
  bool _running = false;
  bool _virtualBackfillDone = false; // 惰性回填只做一次

  /// 告警出口（由 AppState 装配，负责持久化 + Webhook）
  void Function(Alert alert)? onAlert;

  // —— 并发控制 ——
  final int _maxConcurrent = Constants.maxConcurrentConnections;
  final int _maxQueued = Constants.maxQueuedConnections;
  int _active = 0;
  final List<Completer<void>> _queue = [];

  ProxyServer({
    required this.keyManager,
    required this.loadBalancer,
    required this.logService,
    required this.ruleEngine,
    required this.quotaMonitor,
    required this.settings,
    CacheManager? cache,
    RateLimiter? rateLimiter,
    ReportService? reportService,
    this.updateService,
    ModelRepository? modelRepository,
    this.port = Constants.defaultPort,
    this.host = Constants.defaultHost,
    this.loadBalanceStrategy = 'round_robin',
  }) : _modelRepositoryOverride = modelRepository {
    this.cache = cache ??
        CacheManager(
          enabled: settings.cacheEnabled,
          ttl: Duration(seconds: settings.cacheTtlSeconds),
          maxEntries: settings.cacheMaxEntries,
        );
    this.rateLimiter = rateLimiter ??
        RateLimiter(
          enabled: settings.rateLimitEnabled,
          burstMultiplier: settings.burstMultiplier,
          tokensPerMinutePerKey: settings.tokenRateLimitPerMinute,
          requestsPerMinutePerIp: settings.ipRateLimitPerMinute,
          globalRequestsPerMinute: settings.globalRpmLimit,
          adaptiveTpmEnabled: settings.adaptiveTpmEnabled,
        );
    this.reportService =
        reportService ?? ReportService(logService, cacheManager: this.cache);
  }

  bool get isRunning => _running;

  int get activeKeyCount =>
      keyManager.getAll().where((k) => k.status == KeyStatus.active).length;

  int get queuedRequests => _queue.length;

  /// 实时日志流（供 UI 订阅）
  Stream<RequestLog> get logStream => logService.stream;

  List<RequestLog> get recentLogs => logService.recent;

  // ————————————————————————————————————————————
  // 启动 / 停止
  // ————————————————————————————————————————————

  Future<void> start() async {
    if (_running) return;
    _server = await HttpServer.bind(host, port);
    port = _server!.port; // 记录实际绑定的端口（port:0 时为系统分配的临时端口）
    _running = true;
    _server!.listen(_handleRequest, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _running = false;
    _queue.clear();
    _active = 0;
  }

  /// 重启服务（监听地址 / 端口变更后调用，使新配置立即生效）
  Future<void> restart() async {
    await stop();
    await start();
  }

  // ————————————————————————————————————————————
  // 并发信号量
  // ————————————————————————————————————————————

  Future<void> _acquire() async {
    if (_active < _maxConcurrent) {
      _active++;
      return;
    }
    if (_queue.length >= _maxQueued) {
      throw const _ProxyOverload();
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future; // 被唤醒后直接占用一个槽位（所有权转移，不另增 _active）
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  // ————————————————————————————————————————————
  // 请求处理
  // ————————————————————————————————————————————

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      await _acquire();
    } on _ProxyOverload {
      await _respondError(request, 429, '请求过于繁忙，请稍后再试');
      _recordLog(request, null, 'proxy', 429, 0,
          error: 'concurrency limit');
      return;
    }

    final stopwatch = Stopwatch()..start();
    try {
      await _serve(request, stopwatch);
    } finally {
      stopwatch.stop();
      _release();
    }
  }

  Future<void> _serve(HttpRequest request, Stopwatch stopwatch) async {
    final path = request.uri.path;

    // 健康检查
    if (Constants.healthPaths.contains(path)) {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'version': Constants.appVersion,
          'active_keys': activeKeyCount,
          'load_balance': loadBalanceStrategy,
          'queued': queuedRequests,
          'ts': DateTime.now().millisecondsSinceEpoch,
        }));
      await request.response.close();
      return;
    }

    // 管理接口（统计 / 版本 / 在线更新 / 报表 / 缓存），不转发到上游
    if (Constants.adminPaths.contains(path)) {
      await _serveAdmin(request, path);
      return;
    }

    // 聚合模型列表（REQ-003）：AI 应用从中转站获取可用模型，不转发上游
    if (path == Constants.modelsPath) {
      await _serveModels(request);
      return;
    }

    // 入口限流：IP / 全局（需求 2.2.6）
    final clientIp = request.connectionInfo?.remoteAddress.address ?? '';
    final inbound = rateLimiter.checkInbound(clientIp);
    if (!inbound.allowed) {
      request.response.headers
          .set(Constants.retryAfterHeader, '${inbound.retryAfterSeconds}');
      await _respondError(request, 429,
          inbound.message.isEmpty ? '请求过于频繁' : inbound.message);
      _recordLog(request, null, Environment.detectProvider(path), 429,
          stopwatch.elapsedMilliseconds,
          error: 'rate limited: ${inbound.dimension}',
          rateLimited: inbound.dimension);
      _emitRateLimitAlert(inbound, clientIp);
      return;
    }
    rateLimiter.recordInbound(clientIp);

    // 1) 读取请求体（一次性，受上限约束）
    List<int> body;
    try {
      body = await _readBody(request);
    } catch (e) {
      await _respondError(request, 413, '请求体过大或读取失败');
      _recordLog(request, null, Environment.detectProvider(path), 413,
          stopwatch.elapsedMilliseconds,
          error: e.toString());
      return;
    }

    final headers = <String, String>{};
    request.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(', ');
    });

    final payload = RequestPayload.parse(body);
    final proxyRequest = ProxyRequest(
      method: request.method,
      path: path,
      query: request.uri.query,
      headers: headers,
      body: body,
      model: payload.model,
      stream: payload.stream,
      clientIp: request.connectionInfo?.remoteAddress.address ?? '',
    );

    // 2) 规则引擎：构建上下文并求值
    final ctx = RuleEngine.buildContext(proxyRequest);
    final detected =
        Environment.detectProvider(path, model: payload.model, headerProvider: headers[Constants.providerHeader]);
    ctx['request']['provider'] = detected;
    RoutingDecision? decision;
    if (settings.rulesEnabled) {
      decision = ruleEngine.evaluate(ctx);
    }

    // 命中拦截规则
    if (decision?.block == true) {
      await _respondError(
        request,
        403,
        decision?.blockReason ?? '请求被路由规则拦截',
      );
      _recordLog(request, null, detected, 403, stopwatch.elapsedMilliseconds,
          model: payload.model, ruleName: decision?.ruleName, error: 'blocked');
      return;
    }

    // 3) 响应缓存查询（需求 2.2.4）——流式请求不参与缓存
    final cacheKey = CacheManager.buildKey(
      method: request.method,
      path: path,
      query: request.uri.query,
      provider: decision?.provider ?? detected,
      body: body,
    );
    if (cache.enabled && !payload.stream) {
      final hit = cache.get(cacheKey);
      if (hit != null) {
        await _respondFromCache(request, hit);
        _recordLog(
          request,
          null,
          hit.provider.isEmpty ? detected : hit.provider,
          hit.statusCode,
          stopwatch.elapsedMilliseconds,
          model: payload.model,
          requestBytes: body.length,
          responseBytes: hit.body.length,
          ruleName: decision?.ruleName,
          cached: true,
        );
        return;
      }
    }

    // 4) 候选 key 选择 + 多提供商失败重试
    final forwardResult =
        await _forwardWithFallback(proxyRequest, detected, decision);
    if (forwardResult is _ForwardFailure) {
      final msg = forwardResult.lastError != null
          ? '上游转发失败：${forwardResult.lastError}'
          : forwardResult.reason;
      // 可恢复 TPM 限流且已等待预算耗尽：返回 429 + Retry-After，
      // 让 AI 客户端排队后自动重发，而不是硬断成 503（避免“发送继续后仍可用”的中断）。
      if (forwardResult.retryAfterSeconds > 0) {
        // 提示客户端等待后重试（OpenAI/Anthropic 认可的标准做法）
        request.response.headers
            .set(Constants.retryAfterHeader, '${forwardResult.retryAfterSeconds}');
        await _respondError(request, 429, msg);
        _recordLog(request, null, detected, 429, stopwatch.elapsedMilliseconds,
            model: payload.model,
            actualModel: forwardResult.actualModel,
            ruleName: decision?.ruleName,
            error: forwardResult.lastError ?? 'upstream tpm rate limited',
            rateLimited: 'upstream_tpm');
        return;
      }
      await _respondError(request, 503, msg);
      _recordLog(request, null, detected, 503, stopwatch.elapsedMilliseconds,
          model: payload.model,
          actualModel: forwardResult.actualModel,
          ruleName: decision?.ruleName,
          error: forwardResult.lastError ?? forwardResult.reason);
      return;
    }
    final outcome = forwardResult as _ForwardOutcome;

    // 5) 透传响应（SSE 流式 / 普通 JSON）
    final key = outcome.key;
    final result = outcome.result;
    final isError = result.statusCode < 200 || result.statusCode >= 400;
    try {
      request.response.statusCode = result.statusCode;
      result.headers.forEach((name, value) {
        final lower = name.toLowerCase();
        if (BaseHttpProvider.skipResponseHeader(lower)) return;
        request.response.headers.set(name, value);
      });

      if (cache.enabled) {
        request.response.headers.set(Constants.cacheHitHeader, 'MISS');
      }

      final cap = result.streaming
          ? Constants.usageCaptureBytes
          : Constants.maxRequestBodyBytes;
      final written = await _pipeAndCapture(result.body, request.response, cap);

      final usage = UsageParser.parseBytes(written.captured);
      final prevStatus = key.status;
      if (!isError) {
        loadBalancer.recordSuccess(key, latencyMs: stopwatch.elapsedMilliseconds);
      } else {
        loadBalancer.recordFailure(key);
      }

      // 6) 写入缓存（仅完整捕获的非流式 2xx 响应）
      if (cache.isCacheable(
        method: request.method,
        statusCode: result.statusCode,
        streaming: result.streaming,
        bodyBytes: written.total,
      )) {
        if (written.captured.length == written.total) {
          cache.put(
            cacheKey,
            statusCode: result.statusCode,
            headers: result.headers,
            body: written.captured,
            provider: key.provider,
            model: payload.model,
          );
        }
      }

      // 7) 额度记账（仅成功计入 token；失败仅计请求数）
      final alerts = quotaMonitor.recordUsage(
        key,
        tokens: isError ? 0 : usage.total,
        error: isError,
      );
      if (!isError) rateLimiter.recordTokens(key, usage.total, model: payload.model);
      await keyManager.updateKey(key);
      _maybeEmitKeyStatusChanged(key, prevStatus);
      for (final a in alerts) {
        onAlert?.call(a);
      }

      _recordLog(
        request,
        key,
        key.provider,
        result.statusCode,
        stopwatch.elapsedMilliseconds,
        model: payload.model,
        actualModel: outcome.actualModel,
        promptTokens: usage.promptTokens,
        completionTokens: usage.completionTokens,
        requestBytes: body.length,
        responseBytes: written.total,
        streaming: result.streaming,
        retries: outcome.attempts,
        ruleName: decision?.ruleName,
        error: isError ? 'upstream ${result.statusCode}' : null,
      );
      await request.response.close();
    } catch (e) {
      // 异常时兜底：关闭下游响应、排空上游流，避免连接泄漏
      try {
        await result.body.drain<void>();
      } catch (_) {}
      try {
        await request.response.close();
      } catch (_) {}
      _recordLog(
        request,
        key,
        key.provider,
        isError ? result.statusCode : 0,
        stopwatch.elapsedMilliseconds,
        model: payload.model,
        actualModel: outcome.actualModel,
        retries: outcome.attempts,
        ruleName: decision?.ruleName,
        error: e.toString(),
      );
    }
  }

  /// 候选 key 选择 + 多提供商失败重试
  ///
  /// 成功返回 [_ForwardOutcome]；失败返回 [_ForwardFailure]（含具体原因，
  /// 便于 503 响应与日志向用户说明「为什么没有可用 key」）。
  Future<Object> _forwardWithFallback(
    ProxyRequest proxyRequest,
    String detected,
    RoutingDecision? decision,
  ) async {
    final primaryName = decision?.provider ?? detected;
    var candidates = Environment.candidateProviders(primaryName, proxyRequest.path);
    final strategy = decision?.strategy ?? loadBalanceStrategy;

    // P0：若请求的是能力虚拟模型（virtualId / 品牌别名），先解析为「提供商 → 真实模型名」，
    // 候选池按虚拟模型的提供商收窄，转发时改写模型名。
    // 该能力仅在「虚拟模型层」开启时生效；默认关闭时跳过，保证请求模型名原样透传（纯转发）。
    final virtualId = settings.virtualModelsEnabled
        ? ModelNormalizer.resolveRequestModel(proxyRequest.model)
        : null;
    // provider 名 → 该提供商下该虚拟模型应使用的真实模型名
    final Map<String, String> virtualActualByProvider = <String, String>{};
    if (virtualId != null) {
      for (final m in modelRepository.getEnabled()) {
        // 跳过「模型名本身就是虚拟 ID」的条目：若用它作为改写目标，
        // _rewriteModel 会因 actualModel == req.model 而跳过改写，
        // 导致虚拟 ID 被透传给上游 → 上游 404 model not found。
        if (m.virtualId == virtualId &&
            m.name != m.virtualId &&
            virtualActualByProvider[m.provider] == null) {
          virtualActualByProvider[m.provider] = m.name;
        }
      }
      // 目录中没有该虚拟模型数据时，回退到内置典型候选（品牌别名也覆盖快捷用法）
      if (virtualActualByProvider.isEmpty) {
        final typical = StandardModelRegistry.virtualTypical[virtualId] ?? const [];
        for (final t in typical) {
          final tp = t['provider']!;
          final tm = t['model']!;
          // 回退候选也要尊重用户对该模型的停用：若目录中该模型已被禁用（速度慢被关掉），
          // 跳过，避免把「已禁用的慢模型」转发到上游 → 上游 404 model not found。
          final local = _findModelByProviderAndName(tp, tm);
          if (local != null && !local.isEnabled) continue;
          virtualActualByProvider[tp] = tm;
        }
      }
      if (virtualActualByProvider.isEmpty) {
        // 虚拟模型没有任何可用的已启用模型：明确告警而不是把假模型透传给上游，
        // 否则上游会回 404 model not found（如 Gemini 的 not_found_error）。
        return _ForwardFailure(
          '虚拟模型「$virtualId」当前没有可用的已启用模型：请先启用/同步该档位下的模型',
          null,
        );
      }
      if (virtualActualByProvider.isNotEmpty) {
        // 收窄候选为「拥有该虚拟模型真实映射」的提供商
        candidates = virtualActualByProvider.keys.toList();
      }
    }

    // 模型归属优先：真实模型名时，优先路由到拥有该模型的提供商
    // （解决多提供商下轮询命中无此模型的 key 导致 upstream 404 model not found）
    final modelOwner =
        virtualId == null ? _findModelOwner(proxyRequest.model) : null;
    if (modelOwner != null && modelOwner != candidates.first) {
      candidates = [modelOwner, ...candidates.where((c) => c != modelOwner)];
    }

    // 构建候选池：每个候选提供商纳入其全部可用 key（一个 _Pair 对应一个 key），
    // 从而支持「同一提供商多个 key 之间的失败重试切换」（需求 2.2 多提供商/多 key 自动切换）。
    final pool = <_Pair>[];
    var hadActiveKeys = false;
    var rateLimited = false;
    var groupFiltered = false;
    for (final pname in candidates) {
      final provider = providerForName(pname);
      final rewriteWhat = virtualActualByProvider[pname]; // 该提供商虚拟改写目标
      // 使用「可用」查询：error 且冷却已过期的 key 会自动恢复为 active，
      // 避免 key 因连续失败被标记 error 后永远无法回到候选池（死锁）。
      var keys = keyManager.getUsableByProvider(pname);
      if (keys.isNotEmpty) hadActiveKeys = true;
      if (decision?.group != null && decision!.group!.isNotEmpty) {
        final before = keys.length;
        keys = keys.where((k) => k.group == decision.group).toList();
        if (before > 0 && keys.isEmpty) groupFiltered = true;
      }
      if (settings.rateLimitEnabled) {
        final before = keys.length;
        // 传模型名，让「自适应 TPM 挡板」按 key+model 学到的上限在候选池阶段生效
        keys = keys
            .where((k) => rateLimiter.allows(k, model: proxyRequest.model))
            .toList();
        if (before > 0 && keys.isEmpty) rateLimited = true;
      }
      final ranked = loadBalancer.rank(keys, strategy);
      for (final k in ranked) {
        pool.add(_Pair(provider, k, rewriteWhat));
      }
    }

    if (pool.isEmpty) {
      String reason;
      if (!hadActiveKeys) {
        // 诊断性提示：说明 key 当前具体处于什么状态、最早何时自动恢复，
        // 避免笼统的「没有 active 状态」让用户无从下手。
        reason = _describeNoUsableKeys(candidates);
      } else if (groupFiltered) {
        reason = '候选 key 均不属于路由规则指定的分组「${decision?.group}」';
      } else if (rateLimited) {
        reason = '候选 key 均被限流拦截（RPM/TPM 达到上限）';
      } else {
        reason = '候选池为空';
      }
      return _ForwardFailure(reason, null);
    }

    // 顺序尝试候选 key，遇到 429/5xx/异常则切换下一个（可循环复用，
    // 直到达到 maxRetryKeys 上限或某次成功/遇到不可重试的 4xx）。
    //
    // 针对「可恢复 TPM 限流」（429 且命中 tpm/tokens_per_minute 关键词）：
    // 不再立刻换 key 或放弃，而是【在同一 key 上等待 TPM 窗口刷新后重试】，
    // 使“发送继续后仍可使用”的请求在第三方客户端侧不中断。等待受总预算
    // [Constants.tpmWaitBudgetMs] 约束，超过预算则返回 429 + Retry-After。
    int attempts = 0;
    int idx = 0;
    String? lastUpstreamError;
    String? lastActualModel; // 最后一次尝试实际发送的模型名
    // 单次请求允许等待 TPM 窗口刷新的总预算截止时间
    final tpmDeadline =
        DateTime.now().millisecondsSinceEpoch + Constants.tpmWaitBudgetMs;
    int? tpmRetryAfter; // 最终建议客户端等待的秒数（遭遇可恢复 TPM 限流时）
    bool sawRecoverable429 = false;
    ApiKey? lastTpmKey; // 最近一次触发可恢复 TPM 429 的 key
    while (attempts < settings.maxRetryKeys) {
      if (pool.isEmpty) break;
      final pair = pool[idx % pool.length];
      idx++;
      final key = pair.key;
      attempts++; // 本次视为一次上游尝试

      // 转发前滚动重置（防止跨日计数失真）
      final rollAlerts = quotaMonitor.rollIfNeeded(key);
      for (final a in rollAlerts) {
        onAlert?.call(a);
      }
      // 已耗尽 / 停用 / 冷却中的 key 跳过本次尝试（仍计入 attempts，避免死循环）
      if (key.status != KeyStatus.active) continue;

      loadBalancer.incConnection(key.id);
      rateLimiter.consumeKey(key);
      lastActualModel = pair.actualModel;
      ProviderResult? result;
      try {
        // 虚拟模型请求：把请求体里的模型名改写为该提供商下的真实模型
        final out =
            _rewriteModel(proxyRequest, pair.actualModel);
        final r = await pair.provider.forward(
          out,
          key,
          timeout: Duration(seconds: settings.upstreamTimeoutSeconds),
        );
        result = r;
        if (r.statusCode >= 200 && r.statusCode < 300) {
          return _ForwardOutcome(key, r, attempts, pair.actualModel);
        }
        // 以下状态码视为可重试，切换下一个 key
        // 404 = model not found on this key/provider, next candidate might have it
        // 429 = rate limited
        // 5xx = server error
        if (r.statusCode == 404 || r.statusCode == 429 || r.statusCode >= 500) {
          // 捕获上游错误响应体（前 500 字节），让日志/503 展示真实原因，
          // 例如 OpenAI 的 "The model 'gpt-4o' does not exist or you do not have access to it"。
          final errBody = await _captureUpstreamError(r.body);
          lastUpstreamError = errBody != null && errBody.isNotEmpty
              ? '上游 HTTP ${r.statusCode}: $errBody'
              : '上游 HTTP ${r.statusCode}';

          // —— 可恢复 TPM 限流：等待窗口刷新后重试同一个 key ——
          if (r.statusCode == 429 &&
              (errBody == null ||
                  RateLimiter.isRecoverableTpmLimit(r.statusCode, errBody)) &&
              Constants.tpmWaitBudgetMs > 0) {
            // 喂给自适应挡板：把本次 429 当“撞线点”下调学到的 TPM 上限
            rateLimiter.recordUpstreamTpmLimit(
                key, proxyRequest.model, rateLimiter.tpmUsed(key));
            sawRecoverable429 = true;
            lastTpmKey = key;
            // 优先采用上游给出的 Retry-After，否则用本地 TPM 窗口剩余时间
            var waitMs = (_retryAfterSecondsFromHeaders(r) * 1000);
            if (waitMs <= 0) waitMs = rateLimiter.tpmWaitMillis(key);
            if (waitMs <= 0) waitMs = 1000; // 最小退避 1s
            // 受总预算约束
            final now = DateTime.now().millisecondsSinceEpoch;
            final budgetLeft = tpmDeadline - now;
            if (waitMs > budgetLeft) {
              waitMs = budgetLeft > 0 ? budgetLeft : 0;
            }
            if (waitMs > 0) {
              // 预算内：等待后重试同一候选（回退 idx，不切换 key、也不冷却该 key）
              idx--;
              await Future<void>.delayed(Duration(milliseconds: waitMs));
              // 绕过 recordFailure：TPM 临时限流不是 key 故障，不该触发冷却
              continue;
            }
            // 预算耗尽：记录重试建议，跳出循环改走 429 + Retry-After
            tpmRetryAfter = (budgetLeft ~/ 1000).clamp(1, 120);
            break;
          }

          // 404 模型不存在：key 本身正常，只是不含该模型，不标记失败（避免误冷却）
          if (r.statusCode != 404) {
            final prev = key.status;
            loadBalancer.recordFailure(key);
            await keyManager.updateKey(key);
            _maybeEmitKeyStatusChanged(key, prev);
          }
          continue;
        }
        // 其余 4xx（除 404）：直接透传上游错误，不重试
        return _ForwardOutcome(key, r, attempts, pair.actualModel);
      } catch (e) {
        lastUpstreamError = e.toString();
        // 异常时若已拿到结果流，先排空以释放连接，避免连接池泄漏
        try {
          await result?.body.drain<void>();
        } catch (_) {}
        final prev = key.status;
        loadBalancer.recordFailure(key);
        await keyManager.updateKey(key);
        _maybeEmitKeyStatusChanged(key, prev);
        continue;
      } finally {
        loadBalancer.decConnection(key.id);
      }
    }
    // 遭遇可恢复 TPM 限流：返回 429 + Retry-After 而非 503。
    // 无论是因为等待预算耗尽，还是 maxRetryKeys 尝试次数用尽但预算尚余，
    // 只要遇过可恢复 TPM 429，就应让客户端等待后重发，而不是硬断 503。
    if (tpmRetryAfter != null || sawRecoverable429) {
      final secs = tpmRetryAfter ??
          (lastTpmKey == null
              ? 5
              : (rateLimiter.tpmWaitMillis(lastTpmKey!) ~/ 1000).clamp(1, 120));
      return _ForwardFailure(
        '上游 TPM 限流，等待 $secs 秒后重试',
        lastUpstreamError,
        lastActualModel,
        secs,
      );
    }
    return _ForwardFailure(
      '上游重试耗尽（${settings.maxRetryKeys} 次尝试均失败）',
      lastUpstreamError,
      lastActualModel,
    );
  }

  /// 从上游响应头读取 `retry-after`（秒），无则返回 0。
  int _retryAfterSecondsFromHeaders(ProviderResult r) {
    for (final e in r.headers.entries) {
      if (e.key.toLowerCase() == 'retry-after') {
        final v = int.tryParse(e.value.trim());
        if (v != null && v > 0) return v;
        // retry-after 也常用 HTTP 日期格式，此处仅认秒数
      }
    }
    return 0;
  }

  // ————————————————————————————————————————————
  // 工具方法
  // ————————————————————————————————————————————

  /// 在本地模型库中查找拥有该模型的提供商（未同步 / 未知模型返回 null）
  ///
  /// 用于请求路由时把「模型归属提供商」排在候选首位，从根源避免
  /// 轮询命中无此模型的 key 导致 upstream 404 model not found。
  String? _findModelOwner(String model) {
    if (model.isEmpty) return null;
    for (final m in modelRepository.getEnabled()) {
      if (m.name == model) return m.provider;
    }
    return null;
  }

  /// 按「提供商 + 模型名」精确查找本地模型（含已禁用/已下线，专供虚拟回退判断）。
  ///
  /// 与 [_findModelOwner] 不同：前者只看已启用模型；这里用于判断某模型
  /// 是否已被用户停用（作为虚拟模型回退候选时需跳过），因此不区分启用状态。
  ModelInfo? _findModelByProviderAndName(String provider, String name) {
    if (name.isEmpty) return null;
    for (final m in modelRepository.getAll()) {
      if (m.provider == provider && m.name == name) return m;
    }
    return null;
  }

  /// 当候选提供商下没有任何可用 key 时，生成诊断性原因。
  ///
  /// 逐个检查候选提供商下 key 的实际状态（冷却中 / 额度耗尽 / 已停用 / 未添加），
  /// 并给出最早自动恢复的大致时间，帮助用户快速定位问题。
  String _describeNoUsableKeys(List<String> candidates) {
    final now = DateTime.now().millisecondsSinceEpoch;
    var total = 0;
    var inCooldown = 0;
    var exhausted = 0;
    var inactive = 0;
    int? earliestRecoverMs;
    for (final pname in candidates) {
      for (final k in keyManager.getByProvider(pname)) {
        total++;
        switch (k.status) {
          case KeyStatus.error:
            if (k.cooldownUntil != null && k.cooldownUntil! > now) {
              inCooldown++;
              if (earliestRecoverMs == null ||
                  k.cooldownUntil! < earliestRecoverMs) {
                earliestRecoverMs = k.cooldownUntil;
              }
            }
            break;
          case KeyStatus.exhausted:
            exhausted++;
            break;
          case KeyStatus.inactive:
            inactive++;
            break;
          case KeyStatus.active:
            break;
        }
      }
    }
    if (total == 0) {
      return '候选提供商（${candidates.join('、')}）下尚未添加任何 key';
    }
    final parts = <String>[];
    if (inCooldown > 0) parts.add('$inCooldown 个 key 冷却中');
    if (exhausted > 0) parts.add('$exhausted 个 key 今日额度已用尽');
    if (inactive > 0) parts.add('$inactive 个 key 已停用');
    if (parts.isEmpty) parts.add('状态异常');
    var msg = '候选提供商（${candidates.join('、')}）无可用 key：${parts.join('、')}';
    if (earliestRecoverMs != null) {
      final minutes = ((earliestRecoverMs - now) / 60000).ceil();
      msg += '；最早约 $minutes 分钟后自动恢复';
    }
    return msg;
  }

  /// 读取请求体（受 [Constants.maxRequestBodyBytes] 约束）
  Future<List<int>> _readBody(HttpRequest request) async {
    final out = <int>[];
    await for (final chunk in request) {
      out.addAll(chunk);
      if (out.length > Constants.maxRequestBodyBytes) {
        throw StateError('request body exceeds limit');
      }
    }
    return out;
  }

  /// 将上游流写入客户端，同时采样前 [cap] 字节用于 token 解析
  ///
  /// idle 超时保护：上游长时间无数据（挂起 / 连接半开 / 上游慢）时主动中断，
  /// 避免客户端无限等待（表现为「回答一个简单问题耗时几十秒」）。
  Future<_Captured> _pipeAndCapture(
      Stream<List<int>> source, IOSink sink, int cap) async {
    var total = 0;
    final captured = <int>[];
    var capturedN = 0;
    const idle = Duration(seconds: Constants.upstreamIdleTimeoutSeconds);
    await for (final chunk in source.timeout(idle)) {
      sink.add(chunk);
      total += chunk.length;
      if (capturedN < cap) {
        final take = chunk.length < (cap - capturedN)
            ? chunk.length
            : (cap - capturedN);
        captured.addAll(chunk.sublist(0, take));
        capturedN += take;
      }
    }
    return _Captured(total, captured);
  }

  /// 捕获上游错误响应体（前 500 字节）用于日志诊断，同时消费完整流以释放连接。
  ///
  /// 返回 null 表示无响应体 / 读取失败。5 秒超时兜底，避免上游挂起拖慢重试。
  Future<String?> _captureUpstreamError(Stream<List<int>> body) async {
    final buf = <int>[];
    try {
      await for (final chunk in body.timeout(const Duration(seconds: 5))) {
        for (final b in chunk) {
          if (buf.length >= 500) break;
          buf.add(b);
        }
      }
    } catch (_) {
      // 超时或流异常：已尽力捕获，忽略
    }
    if (buf.isEmpty) return null;
    return utf8.decode(buf, allowMalformed: true).trim();
  }

  Future<void> _respondError(
      HttpRequest request, int code, String message) async {
    if (request.response.statusCode != code) {
      request.response.statusCode = code;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'error': message}));
    await request.response.close();
  }

  /// 从响应缓存命中后回写客户端（需求 2.2.4）
  Future<void> _respondFromCache(
      HttpRequest request, CachedResponse hit) async {
    request.response.statusCode = hit.statusCode;
    hit.headers.forEach((name, value) {
      final lower = name.toLowerCase();
      if (BaseHttpProvider.skipResponseHeader(lower)) return;
      request.response.headers.set(name, value);
    });
    // 缓存命中标记（与未命中时的 MISS 对称）
    request.response.headers.set(Constants.cacheHitHeader, 'HIT');
    // 转写响应体；content-length 由框架按实际字节重算（已跳过原头）
    request.response.add(hit.body);
    await request.response.close();
  }

  /// 管理接口：版本信息 / 在线更新检查 / 统计报表 / 缓存统计 / 实时状态
  ///
  /// 这些路径不转发到上游，仅在本地由中转站处理。
  Future<void> _serveAdmin(HttpRequest request, String path) async {
    request.response.headers.contentType = ContentType.json;

    switch (path) {
      // — 当前版本信息 —
      case Constants.versionPath:
        await _jsonResponse(request, 200, {
          'version': Constants.appVersion,
          'build_number': Constants.appBuildNumber,
          'platform': UpdateService.detectPlatform(),
        });
        return;

      // — 触发在线更新检查 —
      case Constants.updateCheckPath:
        if (updateService == null) {
          await _respondError(request, 501, '未配置在线更新服务');
          return;
        }
        final result = await updateService!.checkForUpdate();
        if (result.hasUpdate) _emitUpdateAvailable(result);
        await _jsonResponse(request, 200, result.toJson());
        return;

      // — 统计报表（JSON）—
      case Constants.reportPath:
        if (request.method != 'GET') {
          await _respondError(request, 405, '该接口仅支持 GET');
          return;
        }
        final report = reportService.generate();
        await _jsonResponse(request, 200, report.toJson());
        return;

      // — 缓存统计（DELETE 清空）—
      case Constants.cacheStatsPath:
        if (request.method == 'DELETE') {
          cache.clear();
          await _jsonResponse(request, 200,
              {'cleared': true, 'stats': cache.stats.toJson()});
          return;
        }
        await _jsonResponse(request, 200, cache.stats.toJson());
        return;

      // — 实时状态（默认）—
      case Constants.statsPath:
      default:
        await _jsonResponse(request, 200, {
          'version': Constants.appVersion,
          'active_keys': activeKeyCount,
          'queued': queuedRequests,
          'rate_limit': rateLimiter.snapshot(),
          'cache': cache.stats.toJson(),
        });
        return;
    }
  }

  /// 聚合模型列表接口（/v1/models）
  ///
  /// - 默认（虚拟模型层关闭，纯转发）：返回全部真实模型明细，客户端可直接用这些模型名请求。
  /// - 虚拟模型层开启时：/v1/models 默认收敛为少量「能力虚拟模型」（chat-premium 等约 10 条），
  ///   客户端请求虚拟 id，代理改写成真实模型；`?expand=1` 仍返回真实模型明细。
  ///
  /// 仍支持 ?provider= / ?capability= / ?status= / ?enabled= 过滤，
  /// 过滤作用于真实模型之上，再按虚拟模型聚合。
  Future<void> _serveModels(HttpRequest request) async {
    // 惰性回填：一次性把老数据（virtualId 仍为 null 的启用模型）归一化归类。
    // 仅在虚拟模型层开启时才有意义；关闭时不做任何归一化写入（纯转发）。
    if (settings.virtualModelsEnabled && !_virtualBackfillDone) {
      _virtualBackfillDone = true;
      await modelRepository.backfillVirtualIds();
    }
    final q = request.uri.queryParameters;
    final expand = const {'1', 'true', 'yes'}.contains(q['expand']);
    final provider = q['provider'];
    final capability = q['capability'];
    final status = q['status'];
    final enabledOnly = (q['enabled'] ?? 'true') != 'false';
    final models = modelRepository.getFiltered(
      provider: provider,
      capability: capability,
      status: status != null && status != 'all' ? status : null,
      enabledOnly: enabledOnly,
    );

    final Object data;
    if (expand || !settings.virtualModelsEnabled) {
      // 明细模式 / 虚拟模型层关闭：返回真实模型（调试 / 精确模型名场景），
      // 每条附 provider 与（如有）virtual_id。关闭虚拟模型层时默认即此模式，
      // 保证 AI 客户端拿到的是可直接请求的真实模型名（纯转发）。
      data = models.map((m) => m.toOpenAIFormat()).toList();
    } else {
      // 收敛模式（虚拟模型层开启时）：按 virtualId 聚合为少量能力模型。
      // 对 virtualId 仍为 null 的模型即时兜底归类（别名 → 名称关键词 → 能力），
      // 保证「只要模型可识别，就一定能收敛到某个档位」，避免客户端只拉到 1~2 个模型。
      final byVirtual = <String, List<ModelInfo>>{};
      for (final m in models) {
        final vid = m.virtualId ??
            ModelNormalizer.assignByModelName(m.name) ??
            ModelNormalizer.assignByCapabilities(m.capabilities);
        if (vid == null) continue;
        byVirtual.putIfAbsent(vid, () => []).add(m);
      }
      data = byVirtual.entries.map((e) => _renderVirtualModel(e.key, e.value)).toList();
    }

    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'object': 'list', 'data': data}));
    await request.response.close();
  }

  /// 把一个虚拟模型档位渲染成 OpenAI 兼容条目
  Map<String, dynamic> _renderVirtualModel(
      String virtualId, List<ModelInfo> members) {
    final std = StandardModelRegistry.byId[virtualId];
    final capabilities = <String>{};
    for (final m in members) {
      capabilities.addAll(m.capabilities);
    }
    if (std != null) capabilities.addAll(std.features);
    final providers = members.map((m) => m.provider).toSet().toList()..sort();
    return {
      'id': virtualId,
      'object': 'model',
      'created': members.first.createdAt ?? 0,
      'owned_by': 'relaygo',
      'permission': <Object>[],
      'root': virtualId,
      'parent': null,
      // 扩展字段
      'virtual': true,
      'display_name': std?.displayName ?? virtualId,
      'capabilities': capabilities.toList()..sort(),
      'providers': providers,
      'model_count': members.length,
    };
  }

  /// 请求体模型名改写：把 virtualId 改写为上游真实模型名。
  ///
  /// 仅在请求体是 JSON 且含 `model` 文本字段时改写；其余（无 body、非 JSON、
  /// 无 model 字段、或无需改写）原样返回原请求对象，避免破坏非 chat 类请求体。
  ProxyRequest _rewriteModel(ProxyRequest req, String? actualModel) {
    if (actualModel == null || actualModel.isEmpty || actualModel == req.model) {
      return req;
    }
    if (req.body.isEmpty || req.model.isEmpty) return req;
    try {
      final text = utf8.decode(req.body, allowMalformed: false);
      final obj = jsonDecode(text);
      if (obj is! Map<String, dynamic>) return req;
      final cur = obj['model'];
      if (cur is! String) return req;
      obj['model'] = actualModel;
      return ProxyRequest(
        method: req.method,
        path: req.path,
        query: req.query,
        headers: req.headers,
        body: utf8.encode(jsonEncode(obj)),
        model: actualModel,
        stream: req.stream,
        clientIp: req.clientIp,
      );
    } catch (_) {
      return req; // 无法解析/编码时原样透传，交由上游处理
    }
  }

  /// 以 JSON 写入响应并关闭
  Future<void> _jsonResponse(
      HttpRequest request, int code, Map<String, dynamic> body) async {
    request.response.statusCode = code;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  /// 触发限流时产生一条告警（需求 2.2.6）
  void _emitRateLimitAlert(RateLimitResult inbound, String clientIp) {
    onAlert?.call(Alert(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      event: AlertEvent.rateLimited,
      level: AlertLevel.warning,
      title: L10n.fmt('触发限流（{dimension}）', {'dimension': inbound.dimension}),
      message: L10n.fmt('来源 {ip} 因「{dim}」被限流：{msg}',
          {'ip': clientIp, 'dim': inbound.dimension, 'msg': inbound.message}),
      data: {
        'dimension': inbound.dimension,
        'client_ip': clientIp,
        'retry_after': inbound.retryAfterSeconds,
      },
    ));
  }

  /// 发现新版本时产生一条告警（供 Webhook / 通知）
  void _emitUpdateAvailable(UpdateCheckResult result) {
    final release = result.release;
    onAlert?.call(Alert(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      event: AlertEvent.updateAvailable,
      level: result.mustUpdate ? AlertLevel.critical : AlertLevel.info,
      title: L10n.fmt('发现新版本 {version}',
          {'version': release?.displayVersion ?? ''}),
      message: release?.releaseNotes.isNotEmpty == true
          ? release!.releaseNotes
          : L10n.tr('有可用更新'),
      data: {
        'version': release?.version ?? '',
        'build_number': release?.buildNumber ?? 0,
        'channel': release?.channel ?? '',
        'mandatory': result.mustUpdate,
        'below_min_supported': result.belowMinSupported,
      },
    ));
  }

  /// Key 状态变更时产生告警（需求 2.2.5：key.status_changed 事件）
  void _maybeEmitKeyStatusChanged(ApiKey key, KeyStatus prev) {
    if (key.status == prev) return;
    onAlert?.call(Alert(
      id: 'keystatus-${key.id}-${DateTime.now().microsecondsSinceEpoch}',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      event: AlertEvent.keyStatusChanged,
      level: key.status == KeyStatus.active
          ? AlertLevel.info
          : AlertLevel.warning,
      title: 'Key ${key.name} 状态变更',
      message: '${_statusLabel(prev)} → ${_statusLabel(key.status)}',
      keyId: key.id,
      data: {
        'provider': key.provider,
        'from': prev.name,
        'to': key.status.name,
      },
    ));
  }

  static String _statusLabel(KeyStatus s) {
    switch (s) {
      case KeyStatus.active:
        return '正常';
      case KeyStatus.error:
        return '异常';
      case KeyStatus.exhausted:
        return '额度耗尽';
      case KeyStatus.inactive:
        return '已停用';
    }
  }

  void _recordLog(
    HttpRequest request,
    ApiKey? key,
    String provider,
    int statusCode,
    int durationMs, {
    String? model,
    String? actualModel,
    int promptTokens = 0,
    int completionTokens = 0,
    int requestBytes = 0,
    int responseBytes = 0,
    bool streaming = false,
    int retries = 0,
    String? ruleName,
    String? error,
    bool cached = false,
    String rateLimited = '',
  }) {
    final log = RequestLog(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      method: request.method,
      path: request.uri.path,
      provider: provider,
      keyId: key?.id ?? '',
      keyName: key?.name ?? '',
      keyMasked: key?.maskedKey ?? '****',
      model: model ?? '',
      actualModel: actualModel ?? '',
      statusCode: statusCode,
      durationMs: durationMs,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      requestBytes: requestBytes,
      responseBytes: responseBytes,
      streaming: streaming,
      retries: retries,
      ruleName: ruleName,
      error: error,
      cached: cached,
      rateLimited: rateLimited,
    );
    logService.add(log);
  }
}

class _ForwardOutcome {
  final ApiKey key;
  final ProviderResult result;
  final int attempts;
  final String? actualModel; // 实际转发到上游的模型名（虚拟模型改写后）
  _ForwardOutcome(this.key, this.result, this.attempts, [this.actualModel]);
}

/// 转发失败（含具体原因，供 503 响应与日志展示）
class _ForwardFailure {
  final String reason;
  final String? lastError;
  final String? actualModel; // 最后一次尝试实际发送的模型名
  /// 非空且 >0 时表示应返回「上游 TPM 限流，建议客户端等待后重试」，
  /// 由调用方用 429 + Retry-After 响应（而非硬断 503）。
  final int retryAfterSeconds;
  const _ForwardFailure(
    this.reason,
    this.lastError, [
    this.actualModel,
    this.retryAfterSeconds = 0,
  ]);
}

class _Captured {
  final int total;
  final List<int> captured;
  _Captured(this.total, this.captured);
}

class _ProxyOverload {
  const _ProxyOverload();
}
