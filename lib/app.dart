import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/config/theme.dart';
import 'package:relaygo/database/database_helper.dart';
import 'package:relaygo/database/provider_repository.dart';
import 'package:relaygo/models/alert.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/models/provider_definition.dart';
import 'package:relaygo/models/routing_rule.dart';
import 'package:relaygo/models/user_settings.dart';
import 'package:relaygo/services/key_manager.dart';
import 'package:relaygo/services/load_balancer.dart';
import 'package:relaygo/services/log_service.dart';
import 'package:relaygo/services/quota_monitor.dart';
import 'package:relaygo/services/rule_engine.dart';
import 'package:relaygo/services/proxy_server.dart';
import 'package:relaygo/services/keep_alive.dart';
import 'package:relaygo/services/update_service.dart';
import 'package:relaygo/services/free_api_service.dart';
import 'package:relaygo/database/model_repository.dart';
import 'package:relaygo/services/model_sync_service.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/app_release.dart';
import 'package:relaygo/l10n/app_strings.dart';
import 'package:relaygo/screens/home_screen.dart';

/// 全局应用状态（状态管理入口）
class AppState extends ChangeNotifier {
  late final KeyManager keyManager;
  late final LoadBalancer loadBalancer;
  late final LogService logService;
  late final RuleEngine ruleEngine;
  late final QuotaMonitor quotaMonitor;
  late final ProxyServer proxy;
  late final UpdateService updateService;
  late final FreeApiService freeApiService;
  late final ModelRepository modelRepository;
  late final ModelSyncService modelSync;
  late final ProviderRepository providerRepository;
  late UserSettings settings;
  Timer? _autoSyncTimer;
  Timer? _keyRecoveryTimer;
  Timer? _updateCheckTimer; // 定期后台检查更新（24h）
  Timer? _watchdogTimer; // 保活看门狗：代理服务异常退出时自动重启
  bool _userWantsRunning = false; // 用户是否期望代理持续运行（看门狗依据）
  DateTime? _serverStartedAt; // 服务最近一次启动时间（用于首页运行时长）
  List<ApiKey> keys = [];

  final StreamController<Alert> _alertController =
      StreamController<Alert>.broadcast();
  final Box<dynamic> _alertsBox;
  final Box<dynamic> _rulesBox;

  AppState({Box<dynamic>? alertsBox, Box<dynamic>? rulesBox})
      : _alertsBox = alertsBox ?? DatabaseHelper.alerts,
        _rulesBox = rulesBox ?? DatabaseHelper.rules {
    keyManager = KeyManager(DatabaseHelper.keys);
    loadBalancer = LoadBalancer();
    providerRepository = ProviderRepository(DatabaseHelper.providers);
    settings = _loadSettings();
    logService = LogService(
      DatabaseHelper.logs,
      maxEntries: settings.maxLogEntries,
      retentionDays: settings.logRetentionDays,
    );
    ruleEngine = RuleEngine(rules: _loadRules());
    quotaMonitor = QuotaMonitor(
      settings: settings,
      onAlert: _handleAlert,
    );
    updateService = _buildUpdateService(settings);
    freeApiService = FreeApiService();
    modelRepository = ModelRepository(DatabaseHelper.models);
    modelSync = ModelSyncService(keyManager, modelRepository,
        historyBox: DatabaseHelper.syncHistory);
    proxy = ProxyServer(
      keyManager: keyManager,
      loadBalancer: loadBalancer,
      logService: logService,
      ruleEngine: ruleEngine,
      quotaMonitor: quotaMonitor,
      settings: settings,
      updateService: updateService,
      modelRepository: modelRepository,
      port: settings.port,
      host: settings.host,
      loadBalanceStrategy: settings.loadBalanceStrategy,
    );
    proxy.onAlert = _handleAlert;
    _startupAlerts();
    L10n.instance.language = settings.language;
    refreshKeys();
    if (settings.autoCheckUpdate) {
      unawaited(_autoCheckUpdate());
      _startPeriodicUpdateCheck();
    }
    if (settings.autoSyncModelsOnStartup) unawaited(_autoSyncModels());
    // 免费 API 推荐：启动时后台检查缓存是否过期（>24h），过期则静默刷新
    unawaited(_autoRefreshFreeApi());
    _scheduleAutoSync();
    _startKeyRecoveryTimer();
    _startWatchdog();
    _maybeAutoStartOnBoot();
  }

  /// 周期性 Key 状态恢复（每 60 秒）：
  ///  - 日/月滚动（恢复 exhausted 的 key）
  ///  - error 且冷却已过期的 key 自动恢复为 active
  ///
  /// 避免「后台无请求时 key 长期停留在 error/exhausted，导致候选池为空」。
  void _startKeyRecoveryTimer() {
    _keyRecoveryTimer?.cancel();
    _keyRecoveryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_recoverKeysPeriodically());
    });
  }

  Future<void> _recoverKeysPeriodically() async {
    var changed = false;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final k in keyManager.getAll()) {
      var dirty = false;
      // 1) 日/月滚动（exhausted 跨日自动恢复）
      final alerts = quotaMonitor.rollIfNeeded(k);
      if (alerts.isNotEmpty) {
        dirty = true;
        for (final a in alerts) {
          _handleAlert(a);
        }
      }
      // 2) error 且冷却已结束 → 恢复为 active
      if (k.status == KeyStatus.error &&
          k.cooldownUntil != null &&
          k.cooldownUntil! <= now) {
        k.status = KeyStatus.active;
        k.cooldownUntil = null;
        k.failureCount = 0;
        dirty = true;
        _handleAlert(Alert(
          id: 'keystatus-$k.id-$now',
          timestamp: now,
          event: AlertEvent.keyStatusChanged,
          level: AlertLevel.info,
          title: 'Key ${k.name} 自动恢复',
          message: '冷却结束，已自动恢复为可用',
          keyId: k.id,
          data: {'provider': k.provider, 'to': 'active'},
        ));
      }
      if (dirty) {
        await keyManager.updateKey(k);
        changed = true;
      }
    }
    if (changed) {
      refreshKeys();
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _keyRecoveryTimer?.cancel();
    _updateCheckTimer?.cancel();
    _watchdogTimer?.cancel();
    super.dispose();
  }

  /// 保活看门狗（每 15 秒）：
  /// 当「用户期望代理运行」但服务意外退出时自动重启，实现崩溃自愈。
  /// 仅在保活开关开启时生效。
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    if (!settings.keepAliveEnabled) return;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_watchdogCheck());
    });
  }

  Future<void> _watchdogCheck() async {
    if (!settings.keepAliveEnabled) return;
    if (!_userWantsRunning) return; // 用户已手动停止，不干预
    if (proxy.isRunning) return;
    // 服务意外退出：自动重启并告警
    try {
      await proxy.start();
      _handleAlert(Alert(
        id: 'watchdog.restart-${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        event: AlertEvent.serverStarted,
        level: AlertLevel.warning,
        title: L10n.tr('代理服务已自动恢复'),
        message: L10n.tr('检测到服务异常退出，看门狗已自动重启'),
      ));
      notifyListeners();
    } catch (e) {
      // 重启失败（如端口被占用）：静默，下个周期再试
    }
  }

  /// 开机自启：仅在用户开启「开机自启」且代理服务未运行时自动启动。
  Future<void> _maybeAutoStartOnBoot() async {
    if (!settings.keepAliveEnabled) return;
    if (!settings.autoStartOnBoot) return;
    if (proxy.isRunning) return;
    await startServer();
  }

  /// 启动代理服务；若开启保活，同时拉起 Android 前台服务。
  Future<void> startServer() async {
    try {
      await proxy.start();
      _userWantsRunning = true;
      _serverStartedAt = DateTime.now();
      if (settings.keepAliveEnabled) {
        unawaited(KeepAliveHelper.start());
      }
      _handleAlert(Alert(
        id: 'server.started.run-${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        event: AlertEvent.serverStarted,
        level: AlertLevel.info,
        title: L10n.tr('代理服务已启动'),
        message: L10n.fmt('监听 {host}:{port}',
            {'host': proxy.host, 'port': '${proxy.port}'}),
      ));
      notifyListeners();
    } catch (e) {
      _handleAlert(Alert(
        id: 'server.start.failed-${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        event: AlertEvent.serverError,
        level: AlertLevel.critical,
        title: L10n.tr('服务启动失败'),
        message: e.toString(),
      ));
      rethrow;
    }
  }

  /// 停止代理服务；若开启保活，同时停止 Android 前台服务。
  Future<void> stopServer() async {
    await proxy.stop();
    _userWantsRunning = false;
    _serverStartedAt = null;
    if (settings.keepAliveEnabled) {
      unawaited(KeepAliveHelper.stop());
    }
    _handleAlert(Alert(
      id: 'server.stopped-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      event: AlertEvent.serverStopped,
      level: AlertLevel.info,
      title: L10n.tr('代理服务已停止'),
      message: '',
    ));
    notifyListeners();
  }

  /// 启动后异步刷新免费 API 推荐缓存（失败静默，保留旧缓存）
  Future<void> _autoRefreshFreeApi() async {
    try {
      await freeApiService.ensureFresh();
    } catch (_) {
      // 网络不通 / 数据异常：静默忽略，页面仍展示本地缓存
    }
  }

  /// 周期性自动同步模型列表（REQ-003）
  ///
  /// 按 [UserSettings.modelSyncIntervalHours] 调度 Timer。仅当「启动时自动同步」
  /// 开启时才生效，使该开关成为「自动同步」的总开关；间隔或开关变更时重建。
  void _scheduleAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    if (!settings.autoSyncModelsOnStartup) return;
    final hours = settings.modelSyncIntervalHours;
    if (hours <= 0) return;
    _autoSyncTimer = Timer.periodic(Duration(hours: hours), (_) {
      unawaited(_autoSyncModels());
    });
  }

  /// 在线更新服务：更新源/渠道跟随设置（方案一 GitHub Releases + 回退清单）
  UpdateService _buildUpdateService(UserSettings s) => UpdateService(
        feedUrl: s.updateFeedUrl,
        githubRepo: s.updateGithubRepo,
        channel: s.updateChannel,
        currentVersion: Constants.appVersion,
        currentBuildNumber: Constants.appBuildNumber,
      );

  Stream<Alert> get alertStream => _alertController.stream;

  UserSettings _loadSettings() {
    final raw = DatabaseHelper.settings.get('user');
    if (raw != null) {
      final s = UserSettings.fromJson(Map<String, dynamic>.from(raw as Map));
      // 旧版本默认监听 127.0.0.1（仅本机），升级为 0.0.0.0
      // 以便局域网内第三方应用访问中转站；用户仍可在设置中改回本机模式。
      if (s.host == '127.0.0.1') {
        return s.copyWith(host: Constants.defaultHost);
      }
      return s;
    }
    return UserSettings();
  }

  List<RoutingRule> _loadRules() {
    final list = _rulesBox.values
        .whereType<Map>()
        .map((m) => RoutingRule.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  void _startupAlerts() {
    if (!settings.alertsEnabled) return;
    _handleAlert(Alert(
      id: 'server.started-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      event: AlertEvent.serverStarted,
      level: AlertLevel.info,
      title: L10n.tr('代理服务已就绪'),
      message: L10n.fmt('监听 {host}:{port}',
          {'host': settings.host, 'port': '${settings.port}'}),
    ));
  }

  /// 启动后异步检查更新（不阻塞 UI），发现新版本时产生告警
  Future<void> _autoCheckUpdate() async {
    try {
      final result = await updateService.checkForUpdate();
      if (result.hasUpdate) _alertUpdateAvailable(result);
    } catch (_) {
      // 网络不通 / 更新源不可达：静默忽略
    }
  }

  /// 定期后台检查更新（方案一：GitHub Releases + 应用内检查）。
  /// 与启动检查共用 [updateService] 的节流逻辑，静默执行、失败不打扰用户。
  void _startPeriodicUpdateCheck() {
    _updateCheckTimer?.cancel();
    _updateCheckTimer = Timer.periodic(
      const Duration(hours: Constants.updatePeriodicCheckHours),
      (_) => unawaited(_autoCheckUpdate()),
    );
  }

  /// 启动后异步同步模型列表（不阻塞 UI），失败静默忽略
  Future<void> _autoSyncModels() async {
    try {
      await modelSync.syncAll(
        autoDisableRemoved: settings.autoDisableRemovedModels,
      );
    } catch (_) {
      // 网络不通 / key 无效：静默忽略，用户可随时手动同步
    }
  }

  /// 供 UI 主动触发「同步所有模型」
  Future<SyncResult> syncModels({
    void Function(SyncProgress)? onProgress,
    bool Function()? isCancelled,
  }) =>
      modelSync.syncAll(
        onProgress: onProgress,
        isCancelled: isCancelled,
        autoDisableRemoved: settings.autoDisableRemovedModels,
      );

  /// 同步单个服务商
  Future<ProviderSyncResult> syncProviderModels(String provider,
          {bool Function()? isCancelled}) =>
      modelSync.syncProvider(provider,
          isCancelled: isCancelled,
          autoDisableRemoved: settings.autoDisableRemovedModels);

  /// 本地模型库（供 UI 直接展示）
  List<ModelInfo> get models => modelRepository.getAll();
  List<ModelInfo> get enabledModels => modelRepository.getEnabled();
  List<Map<String, dynamic>> get syncHistory => modelSync.getHistory();

  /// 供 UI 主动触发检查更新
  Future<UpdateCheckResult> checkForUpdate() async {
    final result = await updateService.checkForUpdate();
    if (result.hasUpdate) _alertUpdateAvailable(result);
    return result;
  }

  void _alertUpdateAvailable(UpdateCheckResult result) {
    final release = result.release;
    _handleAlert(Alert(
      id: 'update-${DateTime.now().microsecondsSinceEpoch}',
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
      },
    ));
  }

  /// 统一告警处理：持久化 + 广播
  void _handleAlert(Alert alert) {
    if (!settings.alertsEnabled) return;
    _alertController.add(alert);
    // 持久化（超出上限时丢弃最旧）
    final count = _alertsBox.length;
    if (count >= Constants.alertsCap) {
      final first = _alertsBox.keys.first;
      _alertsBox.delete(first);
    }
    _alertsBox.put(alert.id, alert.toJson());
  }

  bool get serverRunning => proxy.isRunning;

  /// 服务最近一次启动时间（未运行时为 null）
  DateTime? get serverStartedAt => _serverStartedAt;

  List<RoutingRule> get rules => ruleEngine.rules;

  int get activeKeyCount =>
      keys.where((k) => k.status == KeyStatus.active).length;

  int get totalKeyCount => keys.length;

  /// 未读告警数
  int get unreadAlerts {
    var n = 0;
    for (final v in _alertsBox.values) {
      if (v is Map && (v['read'] != true)) n++;
    }
    return n;
  }

  List<Alert> getAlerts({bool unreadOnly = false}) {
    final list = _alertsBox.values
        .whereType<Map>()
        .map((m) => Alert.fromJson(Map<String, dynamic>.from(m)))
        .where((a) => !unreadOnly || !a.read)
        .toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<void> markAlertRead(String id) async {
    final v = _alertsBox.get(id);
    if (v is Map) {
      final alert = Alert.fromJson(Map<String, dynamic>.from(v));
      await _alertsBox.put(id, alert.markRead().toJson());
      notifyListeners();
    }
  }

  /// 全部标记为已读（进入告警中心时调用，退出后首页红点即消失）
  Future<void> markAllAlertsRead() async {
    var changed = false;
    for (final v in _alertsBox.values) {
      if (v is Map && (v['read'] != true)) {
        final alert = Alert.fromJson(Map<String, dynamic>.from(v));
        await _alertsBox.put(alert.id, alert.markRead().toJson());
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> clearAlerts() async {
    await _alertsBox.clear();
    notifyListeners();
  }

  void refreshKeys() {
    keys = keyManager.getAll();
    // 日/月滚动重置（防止后台无请求时计数长期失真）
    for (final k in keys) {
      final alerts = quotaMonitor.rollIfNeeded(k);
      for (final a in alerts) {
        _handleAlert(a);
      }
      if (alerts.isNotEmpty) keyManager.updateKey(k);
    }
    notifyListeners();
  }

  // —— 提供商管理 ——
  List<ProviderDefinition> get providers => providerRepository.getAll();

  List<ProviderDefinition> get customProviders => providerRepository.getCustom();

  ProviderDefinition? getProvider(String id) => providerRepository.byId(id);

  Future<void> saveProvider(ProviderDefinition p) async {
    await providerRepository.save(p);
    notifyListeners();
  }

  Future<void> deleteProvider(String id) async {
    if (providerRepository.isCustom(id)) {
      await providerRepository.delete(id);
      notifyListeners();
    }
  }

  Future<void> toggleServer() async {
    if (proxy.isRunning) {
      await stopServer();
    } else {
      await startServer();
    }
  }

  Future<ApiKey> addKey({
    required String provider,
    required String plainKey,
    required String name,
    String? providerId,
    String? baseUrl,
    String note = '',
    int priority = 100,
    int weight = 1,
    int maxRpm = 60,
    int dailyQuota = 1000000,
    String group = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    final k = await keyManager.createKey(
      provider: provider,
      providerId: providerId,
      plainKey: plainKey,
      name: name,
      baseUrl: baseUrl,
      note: note,
      priority: priority,
      weight: weight,
      maxRpm: maxRpm,
      dailyQuota: dailyQuota,
      metadata: metadata,
    );
    if (group.isNotEmpty) {
      await keyManager.updateKey(k.copyWith(group: group));
    }
    refreshKeys();
    return k;
  }

  Future<void> deleteKey(String id) async {
    // 保留被删 key 的服务商信息，供删除后重同步受影响提供商
    final k = keyManager.getById(id);
    await keyManager.deleteKey(id);
    // 清除该 key 拉取的模型，避免「删 key 后其模型仍残留」
    await modelRepository.removeBySourceKey(id);
    refreshKeys();
    if (k != null) {
      // 重同步：用剩余 key 重新拉取，恢复应保留的模型
      try {
        await modelSync.syncProvider(k.provider, providerId: k.providerId);
      } catch (_) {
        // 网络失败等场景静默处理：模型已清除，等待下次手动同步
      }
    }
  }

  Future<void> updateKey(ApiKey key) async {
    await keyManager.updateKey(key);
    refreshKeys();
  }

  Future<KeyTestOutcome> testKey(ApiKey key) => keyManager.testKey(key);

  /// 批量测试一组 key（需求 2.2），完成后刷新列表
  Future<BatchTestSummary> batchTestKeys(
    List<ApiKey> keys, {
    Future<void> Function(KeyTestRecord record, int done, int total)? onProgress,
    bool Function()? isCancelled,
    int concurrency = 5,
    Duration perKeyTimeout = const Duration(seconds: 10),
    int retries = 1,
  }) async {
    final summary = await keyManager.batchTestKeys(
      keys,
      onProgress: onProgress,
      isCancelled: isCancelled,
      concurrency: concurrency,
      perKeyTimeout: perKeyTimeout,
      retries: retries,
    );
    refreshKeys();
    return summary;
  }

  /// 批量导入 key（明文行，支持 note / base_url）
  Future<int> importKeys(List<Map<String, String>> rows) async {
    final n = await keyManager.importKeys(rows);
    refreshKeys();
    return n;
  }

  /// 一键导出所有 key 为明文 JSON（用于备份 / 重装后导入）
  ///
  /// 返回的 JSON 数组可直接通过「批量导入」恢复（字段与 [importKeys] 兼容）。
  String exportKeysJson() => jsonEncode(keyManager.exportKeys());

  /// 一键禁用所有失败 key（invalid/timeout/error）
  Future<int> bulkDisableInvalid(List<KeyTestRecord> records) async {
    var n = 0;
    for (final r in records) {
      final k = keyManager.getById(r.id);
      if (k == null) continue;
      await keyManager.updateKey(k.copyWith(status: KeyStatus.inactive));
      n++;
    }
    refreshKeys();
    return n;
  }

  /// 一键删除所有失败 key
  Future<int> bulkDeleteInvalid(List<KeyTestRecord> records) async {
    for (final r in records) {
      await keyManager.deleteKey(r.id);
    }
    refreshKeys();
    return records.length;
  }

  // —— 规则管理 ——
  Future<void> addRule(RoutingRule rule) async {
    await _rulesBox.put(rule.id, rule.toJson());
    _syncRules();
  }

  Future<void> updateRule(RoutingRule rule) async {
    await _rulesBox.put(rule.id, rule.toJson());
    _syncRules();
  }

  Future<void> deleteRule(String id) async {
    await _rulesBox.delete(id);
    _syncRules();
  }

  void _syncRules() {
    ruleEngine.setRules(_loadRules());
    notifyListeners();
  }

  // —— 设置 ——
  Future<void> saveSettings(UserSettings s) async {
    final hostChanged = s.host != settings.host || s.port != settings.port;
    final keepAliveChanged = s.keepAliveEnabled != settings.keepAliveEnabled;
    settings = s;
    await DatabaseHelper.settings.put('user', s.toJson());
    proxy.port = s.port;
    proxy.host = s.host;
    proxy.loadBalanceStrategy = s.loadBalanceStrategy;
    logService.maxEntries = s.maxLogEntries;
    logService.retentionDays = s.logRetentionDays;
    quotaMonitor = QuotaMonitor(settings: s, onAlert: _handleAlert);
    updateService.feedUrl = s.updateFeedUrl;
    updateService.channel = s.updateChannel;
    L10n.instance.language = s.language;
    notifyListeners();
    _scheduleAutoSync();
    // 保活开关变更：开启时若代理在运行则拉起前台服务；关闭时停止前台服务
    if (keepAliveChanged) {
      if (s.keepAliveEnabled) {
        _startWatchdog();
        if (proxy.isRunning) unawaited(KeepAliveHelper.start());
      } else {
        _watchdogTimer?.cancel();
        _watchdogTimer = null;
        unawaited(KeepAliveHelper.stop());
      }
    }
    // 监听地址 / 端口变更时，若代理正在运行则自动重启以立即生效
    if (hostChanged && proxy.isRunning) {
      await proxy.restart();
      notifyListeners();
    }
  }

  /// 日志清理（需求 2.2.1）
  Future<int> cleanupLogs() => logService.cleanup();
}

/// 应用根组件
class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Consumer<AppState>(
        builder: (ctx, app, _) {
          // 依赖 settings.language：语言切换时整个 MaterialApp 重建，
          // 保证所有页面（含已入栈路由）立即刷新为新的语言。
          app.settings.language;
          return MaterialApp(
            title: Constants.appName,
            theme: AppTheme.light,
            debugShowCheckedModeBanner: false,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
