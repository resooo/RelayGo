import 'package:flutter/material.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/provider_definition.dart';
import 'package:relaygo/utils/encryption.dart';
import 'package:relaygo/utils/validators.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 添加 / 编辑 API Key 对话框
///
/// [existing] 为 null 表示新增，否则为编辑（key 留空则保持原密文）。
/// 支持需求 1.2 的备注字段（最大 200 字符，自动显示 0/200 计数）。
/// 提供商可从内置 + 自定义提供商列表中选择，自动带入 API URL 与 API 路径。
class KeyEditDialog extends StatefulWidget {
  final AppState app;
  final ApiKey? existing;

  const KeyEditDialog({Key? key, required this.app, this.existing})
      : super(key: key);

  @override
  State<KeyEditDialog> createState() => _KeyEditDialogState();
}

class _KeyEditDialogState extends State<KeyEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _provider;
  late String _providerId;
  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _apiPathCtrl = TextEditingController(text: '/chat/completions');
  final _groupCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _prioCtrl = TextEditingController(text: '100');
  final _weightCtrl = TextEditingController(text: '1');
  final _rpmCtrl = TextEditingController(text: '60');
  final _quotaCtrl = TextEditingController(text: '1000000');

  @override
  void initState() {
    super.initState();
    final k = widget.existing;
    if (k != null) {
      _provider = k.provider;
      _providerId = k.providerId.isEmpty ? k.provider : k.providerId;
      _nameCtrl.text = k.name;
      _urlCtrl.text = k.baseUrl ?? '';
      _apiPathCtrl.text =
          (k.metadata['api_path'] as String?) ?? '/chat/completions';
      _groupCtrl.text = k.group;
      _noteCtrl.text = k.note;
      _prioCtrl.text = '${k.priority}';
      _weightCtrl.text = '${k.weight}';
      _rpmCtrl.text = '${k.maxRequestsPerMinute}';
      _quotaCtrl.text = '${k.dailyQuota}';
    } else {
      // 新增：默认选中第一个提供商
      final providers = widget.app.providers;
      if (providers.isNotEmpty) {
        final first = providers.first;
        _providerId = first.id;
        _provider = _mapToProviderType(first);
        _urlCtrl.text = first.apiUrl;
        _apiPathCtrl.text = first.apiPath;
      } else {
        _provider = 'custom';
        _providerId = 'custom';
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    _apiPathCtrl.dispose();
    _groupCtrl.dispose();
    _noteCtrl.dispose();
    _prioCtrl.dispose();
    _weightCtrl.dispose();
    _rpmCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  /// 选择提供商后自动带入 API URL 与 API 路径
  ///
  /// 切换提供商时总是更新 URL（内置预设带官方地址；azure/custom 预设为空，
  /// 会清空让用户手动填写），避免沿用上一个提供商的地址导致连接错误。
  void _onProviderSelected(ProviderDefinition? p) {
    if (p == null) return;
    setState(() {
      _providerId = p.id;
      _provider = _mapToProviderType(p);
      _urlCtrl.text = p.apiUrl;
      _apiPathCtrl.text = p.apiPath;
    });
  }

  /// 将提供商定义映射为路由用的 ProviderType.name
  String _mapToProviderType(ProviderDefinition p) {
    switch (p.id) {
      case 'openai':
        return 'openai';
      case 'anthropic':
        return 'anthropic';
      case 'google':
        return 'google';
      case 'azure':
        return 'azure';
      default:
        return 'custom';
    }
  }

  /// 构建该提供商的 metadata（api_path / model_list_path / auth 等）
  Map<String, dynamic> _buildMetadata(ProviderDefinition? p) {
    final meta = <String, dynamic>{};
    if (p != null) {
      meta['api_path'] = p.apiPath;
      meta['model_list_path'] = p.modelListPath;
      if (p.authType == 'api-key') {
        meta['auth_header'] = 'api-key';
        meta['auth_prefix'] = '';
      } else {
        meta['auth_header'] = 'authorization';
        meta['auth_prefix'] = 'Bearer ';
      }
    }
    return meta;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final note = _noteCtrl.text.trim();
    final provider = widget.app.getProvider(_providerId);
    final metadata = _buildMetadata(provider);
    final apiPath = _apiPathCtrl.text.trim().isEmpty
        ? '/chat/completions'
        : _apiPathCtrl.text.trim();
    metadata['api_path'] = apiPath;

    if (widget.existing == null) {
      // 新增：支持一行一个 Key 批量添加
      final keys = _keyCtrl.text
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final baseName = _nameCtrl.text.trim();
      final providerName = provider?.name ?? _provider;
      for (var i = 0; i < keys.length; i++) {
        final keyName = keys.length > 1
            ? (baseName.isEmpty
                ? '$providerName-${i + 1}'
                : '$baseName-${i + 1}')
            : (baseName.isEmpty ? providerName : baseName);
        await widget.app.addKey(
          provider: _provider,
          providerId: _providerId,
          plainKey: keys[i],
          name: keyName,
          baseUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
          note: note,
          priority: int.tryParse(_prioCtrl.text) ?? 100,
          weight: int.tryParse(_weightCtrl.text) ?? 1,
          maxRpm: int.tryParse(_rpmCtrl.text) ?? 60,
          dailyQuota: int.tryParse(_quotaCtrl.text) ?? 1000000,
          group: _groupCtrl.text.trim(),
          metadata: metadata,
        );
      }
      navigator.pop(true);
    } else {
      final k = widget.existing!;
      final encrypted = _keyCtrl.text.trim().isEmpty
          ? k.encryptedKey
          : EncryptionUtil.encrypt(_keyCtrl.text.trim());
      await widget.app.updateKey(k.copyWith(
        provider: _provider,
        providerId: _providerId,
        encryptedKey: encrypted,
        name: _nameCtrl.text.trim(),
        note: note,
        baseUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
        group: _groupCtrl.text.trim(),
        priority: int.tryParse(_prioCtrl.text) ?? k.priority,
        weight: int.tryParse(_weightCtrl.text) ?? k.weight,
        maxRequestsPerMinute: int.tryParse(_rpmCtrl.text) ?? k.maxRequestsPerMinute,
        dailyQuota: int.tryParse(_quotaCtrl.text) ?? k.dailyQuota,
        metadata: metadata,
      ));
      navigator.pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final providers = widget.app.providers;
    // 当前选中的提供商（找不到时回退到第一个）
    ProviderDefinition? current = providers
        .where((p) => p.id == _providerId)
        .cast<ProviderDefinition?>()
        .firstWhere((p) => true, orElse: () => null);
    if (current == null && providers.isNotEmpty) {
      current = providers.first;
    }

    return AlertDialog(
      title: Text(isEdit ? L10n.tr('编辑 API Key') : L10n.tr('添加 API Key')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: current?.id,
                items: providers.map((p) {
                  return DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      p.builtIn
                          ? p.name
                          : L10n.fmt('{name} (自定义)', {'name': p.name}),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  _onProviderSelected(widget.app.getProvider(v));
                },
                decoration: InputDecoration(labelText: L10n.tr('提供商')),
              ),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr('名称'),
                  hintText: L10n.tr('留空则自动生成'),
                ),
                validator: (_) => null,
              ),
              TextFormField(
                controller: _keyCtrl,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: L10n.tr('API Key'),
                  hintText: isEdit
                      ? L10n.tr('留空则保持不变')
                      : L10n.tr('支持一行一个 Key 批量添加'),
                ),
                obscureText: true,
                validator: isEdit
                    ? null
                    : (v) {
                        final lines = (v ?? '')
                            .split(RegExp(r'[\r\n]+'))
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                        return lines.isEmpty ? L10n.tr('请填写至少一个 API Key') : null;
                      },
              ),
              TextFormField(
                controller: _urlCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr('API URL'),
                  hintText: L10n.tr('例如 https://api.openai.com/v1'),
                ),
                validator: (v) {
                  if (v!.trim().isEmpty) {
                    return L10n.tr('请填写 API URL');
                  }
                  if (!v.trim().startsWith('http://') &&
                      !v.trim().startsWith('https://')) {
                    return L10n.tr('URL 必须以 http:// 或 https:// 开头');
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _apiPathCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr('API 路径'),
                  hintText: L10n.tr('默认 /chat/completions'),
                ),
              ),
              // 备注说明（需求 1.2）
              TextFormField(
                controller: _noteCtrl,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: L10n.tr('备注说明(可选)'),
                  hintText: L10n.tr('选填，例如：账号A-免费额度'),
                  counterText: '',
                ),
              ),
              TextFormField(
                controller: _groupCtrl,
                decoration: InputDecoration(
                  labelText: L10n.tr('分组(可选)'),
                  hintText: L10n.tr('用于规则按组路由'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _prioCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: L10n.tr('优先级')),
                      validator: (v) => Validators.validatePositiveInt(v, '优先级'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _weightCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: L10n.tr('权重')),
                      validator: (v) => Validators.validatePositiveInt(v, '权重'),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rpmCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: L10n.tr('每分钟上限(RPM)')),
                      validator: (v) => Validators.validatePositiveInt(v, 'RPM'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _quotaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: L10n.tr('每日额度(token)')),
                      validator: (v) => Validators.validatePositiveInt(v, '额度'),
                    ),
                  ),
                ],
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