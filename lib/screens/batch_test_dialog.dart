import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 批量测试 Key 有效性对话框（需求 2.2 / 2.3.2）
///
/// 支持进度实时显示、手动取消、结果汇总（有效/无效/超时），
/// 以及一键禁用 / 删除失败 key、导出结果。
class BatchTestDialog extends StatefulWidget {
  final AppState app;
  final List<ApiKey> keys;
  final String title;

  const BatchTestDialog({
    Key? key,
    required this.app,
    required this.keys,
    this.title = '测试全部 Key',
  }) : super(key: key);

  @override
  State<BatchTestDialog> createState() => _BatchTestDialogState();
}

class _BatchTestDialogState extends State<BatchTestDialog> {
  bool _running = true;
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;
  String _currentName = '';
  final List<KeyTestRecord> _records = [];
  BatchTestSummary? _summary;

  @override
  void initState() {
    super.initState();
    _total = widget.keys.length;
    _run();
  }

  Future<void> _run() async {
    final summary = await widget.app.batchTestKeys(
      widget.keys,
      isCancelled: () => _cancelled,
      onProgress: (rec, done, total) async {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
          _currentName = rec.name;
          _records.add(rec);
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _summary = summary;
    });
  }

  void _cancel() {
    setState(() => _cancelled = true);
  }

  Future<void> _disableAll() async {
    if (_summary == null) return;
    final n = await widget.app.bulkDisableInvalid(_summary!.failed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(L10n.fmt('已禁用 {n} 个无效 Key', {'n': '$n'})),
          backgroundColor: Colors.orange),
    );
    Navigator.pop(context, true);
  }

  Future<void> _deleteAll() async {
    if (_summary == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.tr('删除无效 Key')),
        content: Text(L10n.fmt('确认删除 {n} 个无效/失败 Key？此操作不可撤销。',
            {'n': '${_summary!.failed.length}'})),
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
    if (confirm == true) {
      final n = await widget.app.bulkDeleteInvalid(_summary!.failed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(L10n.fmt('已删除 {n} 个无效 Key', {'n': '$n'})),
            backgroundColor: Colors.red),
      );
      Navigator.pop(context, true);
    }
  }

  void _export() {
    if (_summary == null) return;
    final text = _summary!.toText();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.tr('测试结果')),
        content: SingleChildScrollView(
          child: SelectableText(text, style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(L10n.tr('已复制到剪贴板'))));
            },
            child: Text(L10n.tr('复制')),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L10n.tr('关闭'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.tr(widget.title)),
      content: SizedBox(
        width: double.maxFinite,
        child: _running ? _buildProgress() : _buildSummary(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildProgress() {
    final pct = _total > 0 ? _done / _total : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.fmt('正在测试 {done}/{total} ...',
            {'done': '$_done', 'total': '$_total'})),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: pct, minHeight: 8),
        const SizedBox(height: 8),
        Text(
            L10n.fmt('当前：{name}',
                {
                  'name': _currentName.isNotEmpty
                      ? _currentName
                      : L10n.tr('准备中')
                }),
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildSummary() {
    final s = _summary!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.tr('测试完成！'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('✅ ${L10n.fmt('有效：{n} 个', {'n': '${s.validCount}'})}'),
        Text('❌ ${L10n.fmt('无效：{n} 个', {'n': '${s.invalidCount}'})}'),
        Text('⚠️ ${L10n.fmt('超时：{n} 个', {'n': '${s.timeoutCount}'})}'
            '${s.errorCount > 0 ? '  · ${L10n.fmt('异常：{n} 个', {'n': '${s.errorCount}'})}' : ''}'),
        const Divider(),
        Text(L10n.tr('失败 Key 列表：'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: s.failed.length,
            itemBuilder: (ctx, i) {
              final r = s.failed[i];
              return ListTile(
                dense: true,
                leading: Icon(Icons.error_outline,
                    color: Color(r.outcome.status.colorValue), size: 18),
                title: Text('${r.provider} - ${r.maskedKey}'
                    '${r.note.isNotEmpty ? '（${r.note}）' : ''}',
                    style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                    L10n.fmt('原因：{reason}',
                        {'reason': r.outcome.error ?? r.outcome.status.label}),
                    style: const TextStyle(fontSize: 12, color: Colors.red)),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    if (_running) {
      return [
        TextButton(onPressed: _cancel, child: Text(L10n.tr('取消'))),
      ];
    }
    final s = _summary!;
    return [
      TextButton(onPressed: _export, child: Text(L10n.tr('导出结果'))),
      if (s.failed.isNotEmpty)
        TextButton(
            onPressed: _deleteAll,
            child: Text(L10n.tr('删除无效'),
                style: const TextStyle(color: Colors.red))),
      if (s.failed.isNotEmpty)
        ElevatedButton(
            onPressed: _disableAll, child: Text(L10n.tr('禁用无效'))),
      ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(L10n.tr('完成'))),
    ];
  }
}
