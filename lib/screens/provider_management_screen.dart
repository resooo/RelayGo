import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/l10n/app_strings.dart';
import 'package:relaygo/models/provider_definition.dart';
import 'package:relaygo/database/provider_repository.dart';

/// 提供商管理页面
///
/// 展示内置 + 用户自定义的 AI 服务商列表。
/// 用户可手动添加、编辑、删除自定义提供商。
class ProviderManagementScreen extends StatelessWidget {
  const ProviderManagementScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);
    final providers = app.providers;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr('提供商管理')),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: L10n.tr('内置提供商无法删除，但可被同 ID 自定义覆盖'),
            onPressed: () => _showHelp(context),
          ),
        ],
      ),
      body: providers.isEmpty
          ? Center(child: Text(L10n.tr('暂无提供商')))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: providers.length,
              itemBuilder: (ctx, i) {
                final p = providers[i];
                return _ProviderTile(
                  provider: p,
                  isCustom: app.customProviders.any((c) => c.id == p.id),
                  onTap: () => _editProvider(context, app, p),
                  onDelete: app.customProviders.any((c) => c.id == p.id)
                      ? () => _confirmDelete(context, app, p)
                      : null,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_provider',
        child: const Icon(Icons.add),
        onPressed: () => _editProvider(context, app, null),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.tr('关于提供商')),
        content: Text(
          L10n.tr('内置提供商预设了市面上主流的 AI 服务商信息，可以直接使用。\n\n'
              '如果内置提供商的 API URL 或路径需要修改，可以添加一个同名的自定义提供商来覆盖。\n\n'
              '自定义的提供商可以自由编辑和删除。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.tr('知道了')),
          ),
        ],
      ),
    );
  }

  void _editProvider(BuildContext context, AppState app, ProviderDefinition? existing) {
    showDialog(
      context: context,
      builder: (ctx) => ProviderEditDialog(app: app, existing: existing),
    );
  }

  void _confirmDelete(BuildContext context, AppState app, ProviderDefinition p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.tr('删除提供商')),
        content: Text(L10n.fmt('确认删除「{name}」？\n已关联该提供商的 API Key 需要重新选择提供商。', {'name': p.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.tr('取消')),
          ),
          TextButton(
            onPressed: () {
              app.deleteProvider(p.id);
              Navigator.pop(ctx);
            },
            child: Text(L10n.tr('删除'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  final ProviderDefinition provider;
  final bool isCustom;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ProviderTile({
    Key? key,
    required this.provider,
    required this.isCustom,
    required this.onTap,
    this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              provider.builtIn ? Colors.indigo.withOpacity(0.15) : Colors.teal.withOpacity(0.15),
          child: Icon(
            provider.builtIn ? Icons.cloud : Icons.add_circle,
            color: provider.builtIn ? Colors.indigo : Colors.teal,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                provider.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: provider.builtIn ? Colors.grey.withOpacity(0.15) : Colors.teal.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                provider.builtIn ? L10n.tr('内置') : L10n.tr('自定义'),
                style: TextStyle(
                  fontSize: 11,
                  color: provider.builtIn ? Colors.grey : Colors.teal,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.apiUrl.isEmpty ? L10n.tr('需手动填写 API URL') : provider.apiUrl,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              L10n.fmt('API 路径: {path}', {'path': provider.apiPath}),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        trailing: onDelete != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                onPressed: onDelete,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// 添加/编辑提供商对话框
class ProviderEditDialog extends StatefulWidget {
  final AppState app;
  final ProviderDefinition? existing;

  const ProviderEditDialog({Key? key, required this.app, this.existing})
      : super(key: key);

  @override
  State<ProviderEditDialog> createState() => _ProviderEditDialogState();
}

class _ProviderEditDialogState extends State<ProviderEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _apiUrlCtrl = TextEditingController();
  final _apiPathCtrl = TextEditingController(text: '/chat/completions');
  final _modelListPathCtrl = TextEditingController(text: '/models');

  @override
  void initState() {
    super.initState();
    final k = widget.existing;
    if (k != null) {
      _nameCtrl.text = k.name;
      _apiUrlCtrl.text = k.apiUrl;
      _apiPathCtrl.text = k.apiPath;
      _modelListPathCtrl.text = k.modelListPath;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _apiUrlCtrl.dispose();
    _apiPathCtrl.dispose();
    _modelListPathCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final existing = widget.existing;
    final p = ProviderDefinition(
      id: existing?.id ?? ProviderRepository.genId(),
      name: _nameCtrl.text.trim(),
      apiUrl: _apiUrlCtrl.text.trim(),
      apiPath: _apiPathCtrl.text.trim().isEmpty
          ? '/chat/completions'
          : _apiPathCtrl.text.trim(),
      modelListPath: _modelListPathCtrl.text.trim().isEmpty
          ? '/models'
          : _modelListPathCtrl.text.trim(),
      authType: existing?.authType ?? 'bearer',
      builtIn: existing?.builtIn ?? false,
      createdAt: existing?.createdAt,
    );
    await widget.app.saveProvider(p);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? L10n.tr('编辑提供商') : L10n.tr('添加提供商')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: L10n.tr('名称')),
                validator: (v) => v!.isEmpty ? L10n.tr('请填写名称') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiUrlCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr('API URL'),
                  hintText: L10n.tr('例如 https://api.openai.com/v1'),
                ),
                validator: (v) {
                  if (v!.isEmpty) return L10n.tr('请填写 API URL');
                  if (!v.startsWith('http://') && !v.startsWith('https://')) {
                    return L10n.tr('URL 必须以 http:// 或 https:// 开头');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiPathCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr('API 路径'),
                  hintText: L10n.tr('默认 /chat/completions'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _modelListPathCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr('模型列表路径'),
                  hintText: L10n.tr('默认 /models'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.tr('取消')),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(isEdit ? L10n.tr('保存') : L10n.tr('添加')),
        ),
      ],
    );
  }
}