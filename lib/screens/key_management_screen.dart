import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/config/theme.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/widgets/key_card.dart';
import 'package:relaygo/widgets/provider_logo.dart';
import 'package:relaygo/screens/key_edit_dialog.dart';
import 'package:relaygo/screens/batch_test_dialog.dart';
import 'package:relaygo/screens/key_import_dialog.dart';
import 'package:relaygo/screens/key_export_dialog.dart';
import 'package:relaygo/screens/model_management_screen.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// API Keys 管理页（对应设计稿 API Keys 管理）
///
/// 顶部搜索 + 筛选；按服务商分组卡片（提供商名 + 数量 + 测试全部）；
/// 每组卡片内为 Key 行（状态圆点 + 掩码 Key + 备注 + 状态徽章）；右下 FAB 添加。
class KeyManagementScreen extends StatefulWidget {
  const KeyManagementScreen({Key? key}) : super(key: key);

  @override
  State<KeyManagementScreen> createState() => _KeyManagementScreenState();
}

class _KeyManagementScreenState extends State<KeyManagementScreen> {
  final Map<String, bool> _testing = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ApiKey> _visible(AppState app) {
    var list = app.keys;
    if (_filter.isNotEmpty) {
      list = list.where((k) => k.provider == _filter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((k) {
        return k.name.toLowerCase().contains(q) ||
            k.maskedKey.toLowerCase().contains(q) ||
            k.note.toLowerCase().contains(q) ||
            k.provider.toLowerCase().contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);
    final visible = _visible(app);
    final grouped = <String, List<ApiKey>>{};
    for (final k in visible) {
      grouped
          .putIfAbsent(k.providerId.isEmpty ? k.provider : k.providerId, () => [])
          .add(k);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Keys'),
        actions: [
          // 更多操作：导入 / 导出 Key
          PopupMenuButton<String>(
            tooltip: L10n.tr('更多操作'),
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'import') {
                _showImportDialog(context, app);
              } else if (v == 'export') {
                _exportKeys(context, app);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                  value: 'import', child: Text(L10n.tr('导入 Key'))),
              PopupMenuItem(
                  value: 'export', child: Text(L10n.tr('导出 Key'))),
            ],
          ),
          // 添加（tonal 小按钮，对应设计稿 AppBar 添加）
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              onPressed: () => _showEditDialog(context, app, null),
              icon: const Icon(Icons.add, size: 18),
              label: Text(L10n.tr('添加')),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索 + 筛选（对应设计稿：搜索框 + tune 筛选按钮）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: L10n.tr('搜索 Key...'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                // 筛选按钮（对应设计稿 tune）
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.borderStrong),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: PopupMenuButton<String>(
                    tooltip: L10n.tr('筛选服务商'),
                    icon: const Icon(Icons.tune, size: 20),
                    onSelected: (v) => setState(() => _filter = v),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                          value: '', child: Text(L10n.tr('全部服务商'))),
                      ...ProviderType.values.map((p) => PopupMenuItem(
                            value: p.name,
                            child: Text(p.displayName),
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      app.keys.isEmpty
                          ? L10n.tr('还没有添加任何 Key\n点击右下角按钮新增')
                          : L10n.tr('没有匹配的 Key'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    children: grouped.entries.map((entry) {
                      final provider = ProviderTypeX.fromString(entry.key);
                      final providerDef = app.getProvider(entry.key);
                      final displayName =
                          providerDef?.name ?? provider.displayName;
                      final keys = entry.value;
                      return _providerGroup(
                          context, app, entry.key, displayName, keys);
                    }).toList(),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showEditDialog(context, app, null),
      ),
    );
  }

  /// 服务商分组（对应设计稿：组标题 + 单张卡片内含所有 Key 行）
  Widget _providerGroup(BuildContext context, AppState app, String providerId,
      String displayName, List<ApiKey> keys) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              // 提供商小 Logo
              ProviderLogo(providerId: providerId, providerName: displayName),
              const SizedBox(width: 8),
              Text(displayName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text)),
              const SizedBox(width: 8),
              // 数量（mono-tag）
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  L10n.count(keys.length),
                  style: const TextStyle(
                      fontFamily: AppTheme.monoFontFamily,
                      fontSize: 11.5,
                      color: AppTheme.text2),
                ),
              ),
              const Spacer(),
              // 测试全部（text 小按钮）
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _batchTest(
                    app, keys, L10n.fmt('测试 {name}', {'name': displayName})),
                child: Text(L10n.tr('测试全部')),
              ),
            ],
          ),
        ),
        // 单张卡片（圆角12 · 边框 1px #E0E0E0）
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: List.generate(keys.length, (i) {
              final k = keys[i];
              return Column(
                children: [
                  if (i > 0)
                    const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 26,
                        color: AppTheme.border),
                  KeyCard(
                    key: ValueKey(k.id),
                    apiKey: k,
                    testing: _testing[k.id] ?? false,
                    onTest: () => _testKey(context, app, k),
                    onEdit: () => _showEditDialog(context, app, k),
                    onDelete: () => _confirmDelete(context, app, k),
                    onToggle: () => _toggleKey(app, k),
                  ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _testKey(
      BuildContext context, AppState app, ApiKey k) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing[k.id] = true);
    final outcome = await app.testKey(k);
    setState(() => _testing[k.id] = false);
    if (!mounted) return;
    var msg = L10n.tr('连接完成');
    var color = Colors.grey;
    switch (outcome.status) {
      case KeyTestStatus.valid:
        msg = L10n.fmt('连接成功：{name}', {'name': k.name});
        color = Colors.green;
        break;
      case KeyTestStatus.invalid:
        msg = L10n.fmt('连接失败：{name}（{err}）',
            {'name': k.name, 'err': outcome.error ?? L10n.tr('无效')});
        color = Colors.red;
        break;
      case KeyTestStatus.timeout:
        msg = L10n.fmt('连接超时：{name}', {'name': k.name});
        color = Colors.orange;
        break;
      case KeyTestStatus.error:
        msg = L10n.fmt('连接异常：{name}（{err}）',
            {'name': k.name, 'err': outcome.error ?? L10n.tr('错误')});
        color = Colors.orange;
        break;
    }
    messenger.showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _toggleKey(AppState app, ApiKey k) async {
    final next =
        k.status == KeyStatus.active ? KeyStatus.inactive : KeyStatus.active;
    await app.updateKey(k.copyWith(status: next));
  }

  Future<void> _confirmDelete(
      BuildContext context, AppState app, ApiKey k) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.tr('删除 Key')),
        content: Text(
            L10n.fmt('确认删除「{name}」？此操作不可撤销。', {'name': k.name})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L10n.tr('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L10n.tr('删除'))),
        ],
      ),
    );
    if (confirm == true) await app.deleteKey(k.id);
  }

  Future<void> _showEditDialog(BuildContext context, AppState app, ApiKey? existing) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => KeyEditDialog(app: app, existing: existing),
    );
    // 新增 Key 成功后提醒同步模型列表，并提供直达入口
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10n.tr('Key 已添加，请同步模型列表')),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: L10n.tr('去同步'),
          onPressed: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ModelManagementScreen()));
          },
        ),
      ));
    }
  }

  void _batchTest(AppState app, List<ApiKey> keys, String title) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BatchTestDialog(app: app, keys: keys, title: title),
    );
  }

  /// 批量导入：从文件读取或直接粘贴（调用 [KeyImportDialog]）
  Future<void> _showImportDialog(BuildContext context, AppState app) async {
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => KeyImportDialog(app: app),
    );
    if (n != null && n > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.fmt('成功导入 {n} 个 Key', {'n': '$n'}))));
    }
  }

  /// 一键导出全部 Key：展示 JSON 内容 + 一键复制（移动端无系统保存对话框）
  Future<void> _exportKeys(BuildContext context, AppState app) async {
    if (app.keys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tr('暂无 Key 可导出'))));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => KeyExportDialog(
        jsonContent: app.exportKeysJson(),
        keyCount: app.keys.length,
      ),
    );
  }
}
