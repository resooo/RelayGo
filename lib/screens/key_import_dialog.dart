import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// Key 批量导入对话框
///
/// 提供两种数据来源：
/// 1. **从文件读取**：调用原生文件选择器读取 .txt/.json/.csv
/// 2. **直接粘贴**：手动粘贴文本（原方式）
///
/// 解析逻辑见 [parseImport]，支持 JSON 数组与
/// `provider,key,name,note` / `provider key name note` 文本行两种格式。
class KeyImportDialog extends StatefulWidget {
  final AppState app;
  const KeyImportDialog({Key? key, required this.app}) : super(key: key);

  @override
  State<KeyImportDialog> createState() => _KeyImportDialogState();
}

class _KeyImportDialogState extends State<KeyImportDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;
  int? _preview;

  static final _accept = [
    XTypeGroup(
      label: L10n.tr('文本 / JSON / CSV'),
      extensions: const ['txt', 'json', 'csv'],
    ),
    XTypeGroup(label: L10n.tr('所有文件')),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 打开原生文件选择器并读取内容填入文本框
  Future<void> _pickFile() async {
    final file = await openFile(acceptedTypeGroups: _accept);
    if (file == null) return;
    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = L10n.fmt('读取文件失败：{err}', {'err': '$e'}));
      return;
    }
    if (!mounted) return;
    _ctrl.text = content;
    _onTextChanged();
  }

  void _onTextChanged() {
    final rows = parseImport(_ctrl.text);
    setState(() {
      _preview = rows.isEmpty ? null : rows.length;
      _error = null;
    });
  }

  Future<void> _doImport() async {
    final rows = parseImport(_ctrl.text);
    if (rows.isEmpty) {
      if (!mounted) return;
      setState(() => _error = L10n.tr('未解析到有效 Key'));
      return;
    }
    setState(() => _busy = true);
    int n = 0;
    try {
      n = await widget.app.importKeys(rows);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = L10n.fmt('导入失败：{err}', {'err': '$e'});
      });
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.tr('批量导入 Key')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: Text(L10n.tr('从文件读取')),
                      onPressed: _busy ? null : _pickFile,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                L10n.tr('支持 .txt / .json / .csv，或下方直接粘贴'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const Divider(height: 16),
              Text(L10n.tr('格式说明：'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const Text(
                  '① JSON：[{"provider":"openai","key":"sk-xxx","name":"账号A","note":"免费"}]',
                  style: TextStyle(fontSize: 12)),
              const Text('② 文本：openai,sk-xxx,账号A,免费额度',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                maxLines: 8,
                onChanged: (_) => _onTextChanged(),
                decoration: InputDecoration(
                  hintText: L10n.tr('在此粘贴 Key 列表，或点击「从文件读取」'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_preview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      L10n.fmt('已识别 {n} 个 Key', {'n': '$_preview'}),
                      style: const TextStyle(color: Colors.green, fontSize: 12)),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(L10n.tr('取消'))),
        ElevatedButton(
          onPressed: _busy ? null : _doImport,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(L10n.tr('导入')),
        ),
      ],
    );
  }
}

/// 解析导入文本，返回 provider/key/name/note/base_url 字典列表。
///
/// 与 [KeyManagementScreen] 中的旧实现保持一致的语义：
/// 先尝试 JSON 数组，失败再按逗号/空白分隔的文本行解析。
List<Map<String, String>> parseImport(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  // 尝试 JSON 数组
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is List) {
      return decoded.whereType<Map>().map((m) {
        final map = Map<String, dynamic>.from(m);
        return {
          'provider': '${map['provider'] ?? ''}',
          'provider_id': '${map['provider_id'] ?? ''}',
          'key': '${map['key'] ?? ''}',
          'name': '${map['name'] ?? ''}',
          'note': '${map['note'] ?? ''}',
          'base_url': '${map['base_url'] ?? ''}',
          'group': '${map['group'] ?? ''}',
          'priority': '${map['priority'] ?? ''}',
          'weight': '${map['weight'] ?? ''}',
          'max_requests_per_minute': '${map['max_requests_per_minute'] ?? ''}',
          'daily_quota': '${map['daily_quota'] ?? ''}',
        };
      }).toList();
    }
  } catch (_) {
    // 非 JSON，按文本行解析
  }
  final rows = <Map<String, String>>[];
  for (final line in trimmed.split(RegExp(r'[\r\n]+'))) {
    final l = line.trim();
    if (l.isEmpty) continue;
    final parts = l.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) continue;
    rows.add({
      'provider': parts[0],
      'key': parts[1],
      'name': parts.length > 2 ? parts[2] : '',
      'note': parts.length > 3 ? parts[3] : '',
    });
  }
  return rows;
}
