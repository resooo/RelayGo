import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/config/theme.dart';
import 'package:relaygo/l10n/app_strings.dart';
import 'package:relaygo/models/model_info.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/screens/sync_progress_dialog.dart';

/// 模型管理页（REQ-003）
///
/// 展示从各服务商同步而来的统一模型列表，支持：
/// - 一键「同步全部」与下拉刷新触发同步
/// - 按来源 key 分组、关键字搜索
/// - 单个模型的启用 / 停用开关
/// - 同一 key 下全部模型的一键启用 / 关闭
class ModelManagementScreen extends StatefulWidget {
  const ModelManagementScreen({Key? key}) : super(key: key);

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
  String _query = '';
  bool _syncing = false;

  /// 同步/开关变更后刷新界面（模型数据实时读自仓库）
  void _load() {
    if (mounted) setState(() {});
  }

  int _lastSync(List<ModelInfo> models) {
    var max = 0;
    for (final m in models) {
      if (m.lastSynced > max) max = m.lastSynced;
    }
    return max;
  }

  Future<void> _syncAll() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SyncProgressDialog(app: Provider.of<AppState>(context, listen: false)),
    );
    _load();
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _toggle(ModelInfo m, bool v) async {
    final app = Provider.of<AppState>(context, listen: false);
    await app.modelRepository.setEnabled(m.id, v);
    _load();
  }

  /// 一键启用 / 关闭同一 key（含旧数据 provider 伪组）下所有模型的启用开关
  Future<void> _toggleAll(List<ModelInfo> models, bool enabled) async {
    final app = Provider.of<AppState>(context, listen: false);
    for (final m in models) {
      await app.modelRepository.setEnabled(m.id, enabled);
    }
    _load();
  }

  /// 清理已下线模型（真正删除，避免越积越多）
  Future<void> _cleanupDeprecated() async {
    final app = Provider.of<AppState>(context, listen: false);
    final counts = app.modelRepository.deprecatedCounts();
    final total = counts.values.fold<int>(0, (s, c) => s + c);
    if (total == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.tr('没有需要清理的已下线模型'))),
      );
      return;
    }
    final detail = counts.entries
        .map((e) => L10n.fmt('{provider}：{count} 个',
            {'provider': app.getProvider(e.key)?.name ?? e.key, 'count': '${e.value}'}))
        .join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L10n.tr('清理已下线模型')),
        content: Text(L10n.fmt('将从模型库中删除以下已下线（deprecated）模型：\n\n{detail}\n\n删除后第三方将无法再获取这些模型。', {'detail': detail})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.tr('取消')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.tr('删除')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final removed = await app.modelRepository.removeDeprecated();
    _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.fmt('已清理 {n} 个已下线模型', {'n': '$removed'}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);
    final all = app.models;
    // 按来源 key 分组：同一 key 拉取的模型归一组，支持整组一键启用/关闭。
    // 旧数据（无 sourceKeyId）回退到「provider 伪组」，保证仍可整体启停。
    final keysById = { for (final k in app.keyManager.getAll()) k.id: k };
    final keyGroups = <String, List<ModelInfo>>{};
    for (final m in all) {
      final gid =
          m.sourceKeyId.isNotEmpty ? m.sourceKeyId : '__legacy:${m.provider}';
      keyGroups.putIfAbsent(gid, () => []).add(m);
    }
    final enabledCount = all.where((m) => m.isEnabled).length;
    final deprecatedCount = all.where((m) => m.status == 'deprecated').length;
    final last = _lastSync(all);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr('模型管理')),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            tooltip: L10n.tr('清理已下线模型'),
            onPressed: _cleanupDeprecated,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: L10n.tr('同步历史'),
            onPressed: () => _showHistory(app),
          ),
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: L10n.tr('同步所有模型'),
            onPressed: _syncing ? null : _syncAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _syncAll,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // 概览
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.model_training, color: AppTheme.brandGreen),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              L10n.fmt('模型总数：{total}（已启用 {enabled}）',
                                  {'total': '${all.length}', 'enabled': '$enabledCount'}),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(
                            last > 0
                                ? L10n.fmt('最后同步：{time}', {
                                    'time': DateFormat('yyyy-MM-dd HH:mm')
                                        .format(DateTime.fromMillisecondsSinceEpoch(last))
                                  })
                                : L10n.tr('尚未同步，点击右上角同步模型'),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          if (deprecatedCount > 0) ...[
                            const SizedBox(height: 2),
                            Text(
                              L10n.fmt('已下线 {count} 个，点击右上角清理',
                                  {'count': '$deprecatedCount'}),
                              style: const TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // 搜索
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: L10n.tr('搜索模型名称 / 服务商'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 12),
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(L10n.tr('还没有模型，点击右上角「同步」从各服务商拉取'),
                      style: const TextStyle(color: Colors.grey)),
                ),
              )
            else
              ...keyGroups.entries.map((entry) {
                final gid = entry.key;
                final full = entry.value;
                // 搜索时整组仍展示完整（避免分组数量跳变），仅模型卡按关键字过滤
                final q = _query.toLowerCase();
                final list = q.isEmpty
                    ? full
                    : full
                        .where((m) =>
                            m.name.toLowerCase().contains(q) ||
                            m.provider.toLowerCase().contains(q) ||
                            m.displayName.toLowerCase().contains(q))
                        .toList();
                if (list.isEmpty) return const SizedBox.shrink();
                final first = full.first;
                final key = keysById[gid];
                final providerName = app.getProvider(first.provider)?.name ??
                    ProviderTypeX.fromString(first.provider).displayName;
                final title = key != null ? key.name : providerName;
                final subtitle = key != null ? providerName : L10n.tr('未关联 key');
                final allEnabled = full.every((m) => m.isEnabled);
                final noneEnabled = full.every((m) => !m.isEnabled);
                final triState = allEnabled ? true : (noneEnabled ? false : null);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '$subtitle（${full.length}）',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // 一键启用/关闭该 key 下所有模型
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                allEnabled
                                    ? L10n.tr('全部启用')
                                    : (noneEnabled
                                        ? L10n.tr('全部关闭')
                                        : L10n.tr('部分启用')),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: allEnabled
                                        ? AppTheme.brandGreen
                                        : Colors.grey),
                              ),
                              Switch.adaptive(
                                // null 表示部分启用；Switch 不支持三态，
                                // 退化为「关闭」显示，见 onChanged 的切换逻辑
                                value: triState ?? false,
                                onChanged: (v) => _toggleAll(full, v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ...list.map((m) => _modelCard(m)),
                  ],
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  /// 同步历史（最近 10 次）
  void _showHistory(AppState app) {
    final history = app.syncHistory;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L10n.tr('同步历史')),
        content: SizedBox(
          width: 460,
          child: history.isEmpty
              ? Text(L10n.tr('暂无同步记录'))
              : ListView(
                  shrinkWrap: true,
                  children: history.map((h) {
                    final ts = h['timestamp'] as int? ?? 0;
                    final providers =
                        List<Map>.from((h['providers'] as List?) ?? const []);
                    final failed =
                        providers.where((p) => p['success'] != true).toList();
                    final detail = providers
                        .map((p) {
                          final pid = p['provider'] as String;
                          final pname = app.getProvider(pid)?.name ??
                              ProviderTypeX.fromString(pid).displayName;
                          return p['success'] == true
                              ? L10n.fmt('{name} {count} 个（新增 {new}）', {
                                  'name': pname,
                                  'count': '${p['count']}',
                                  'new': '${p['new']}',
                                })
                              : L10n.fmt('失败：{err}', {'err': '${p['error'] ?? ''}'});
                        })
                        .join('\n');
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        failed.isEmpty ? Icons.check_circle : Icons.warning,
                        color: failed.isEmpty ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      title: Text(
                        '${DateFormat('MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(ts))}  ${L10n.fmt('共 {n} 个模型', {'n': '${h['total_models'] ?? 0}'})}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(detail,
                          style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.tr('关闭')),
          ),
        ],
      ),
    );
  }

  Widget _modelCard(ModelInfo m) {
    final deprecated = m.status != 'active';
    final app = Provider.of<AppState>(context, listen: false);
    final providerDef = app.getProvider(m.provider);
    final providerName =
        providerDef?.name ?? ProviderTypeX.fromString(m.provider).displayName;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(m.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(providerName,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (m.capabilities.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: -8,
                  children: m.capabilities
                      .map((c) => Chip(
                            label: Text(c),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            labelStyle: const TextStyle(fontSize: 11),
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
              ),
            if (deprecated)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(L10n.tr('已下线'),
                    style: const TextStyle(fontSize: 11, color: Colors.red)),
              ),
          ],
        ),
        trailing: Switch(
          value: m.isEnabled,
          onChanged: (v) => _toggle(m, v),
        ),
      ),
    );
  }
}
