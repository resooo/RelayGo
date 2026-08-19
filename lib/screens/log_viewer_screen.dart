import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/config/theme.dart';
import 'package:relaygo/models/request_log.dart';
import 'package:relaygo/services/log_service.dart';
import 'package:relaygo/utils/formatters.dart';
import 'package:relaygo/widgets/log_list_item.dart';
import 'package:relaygo/l10n/app_strings.dart';
import 'package:relaygo/screens/log_detail_screen.dart';

/// 请求日志页（对应设计稿请求日志）
///
/// 顶部筛选按钮（时间 + 状态）+ 日期分隔 + 日志卡片列表。
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({Key? key}) : super(key: key);

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  String _provider = '';
  String _status = 'all';
  final _searchCtrl = TextEditingController();
  List<RequestLog> _logs = [];
  List<StreamSubscription<RequestLog>>? _sub;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilter);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyFilter());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub?.forEach((s) => s.cancel());
    final app = Provider.of<AppState>(context, listen: false);
    _sub = [
      app.logService.stream.listen((_) => _applyFilter()),
    ];
  }

  @override
  void dispose() {
    _sub?.forEach((s) => s.cancel());
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final app = Provider.of<AppState>(context, listen: false);
    final filter = LogFilter(
      provider: _provider,
      status: _status,
      search: _searchCtrl.text.trim(),
    );
    final logs = app.logService.query(filter);
    setState(() {
      _logs = logs;
    });
  }

  Future<void> _export() async {
    final csv = LogService.toCsv(_logs);
    final file = File(
        '${Directory.systemTemp.path}/relay_logs_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(L10n.fmt('已导出 {n} 条到：{path}',
              {'n': '${_logs.length}', 'path': file.path}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr('请求日志')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              onPressed: _export,
              icon: const Icon(Icons.download, size: 18),
              label: Text(L10n.tr('导出')),
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
          // 筛选按钮（对应设计稿：时间筛选 + 状态筛选）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: _filterButton(
                    label: L10n.tr('状态筛选'),
                    value: _status,
                    items: [
                      DropdownMenuItem(
                          value: 'all', child: Text(L10n.tr('全部'))),
                      DropdownMenuItem(
                          value: 'success', child: Text(L10n.tr('成功'))),
                      DropdownMenuItem(
                          value: 'error', child: Text(L10n.tr('错误'))),
                      const DropdownMenuItem(value: '4xx', child: Text('4xx')),
                      const DropdownMenuItem(value: '5xx', child: Text('5xx')),
                    ],
                    onChanged: (v) {
                      setState(() => _status = v ?? 'all');
                      _applyFilter();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _filterButton(
                    label: L10n.tr('服务商'),
                    value: _provider,
                    items: [
                      DropdownMenuItem(
                          value: '', child: Text(L10n.tr('全部'))),
                      const DropdownMenuItem(
                          value: 'openai', child: Text('OpenAI')),
                      const DropdownMenuItem(
                          value: 'anthropic', child: Text('Anthropic')),
                      const DropdownMenuItem(
                          value: 'google', child: Text('Google')),
                      const DropdownMenuItem(
                          value: 'azure', child: Text('Azure')),
                    ],
                    onChanged: (v) {
                      setState(() => _provider = v ?? '');
                      _applyFilter();
                    },
                  ),
                ),
              ],
            ),
          ),
          // 日期分隔
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  Formatters.formatDate(DateTime.now().millisecondsSinceEpoch),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text2,
                  ),
                ),
                const Spacer(),
                Text(
                  L10n.fmt('{n} 条记录', {'n': '${_logs.length}'}),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.text3,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Text(L10n.tr('暂无匹配日志'),
                        style: const TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _logs.length,
                    itemBuilder: (ctx, i) => LogListItem(
                      log: _logs[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LogDetailScreen(log: _logs[i]),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.borderStrong),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          labelStyle:
              const TextStyle(fontSize: 13, color: AppTheme.text2),
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),
        items: items,
        onChanged: onChanged,
        icon: const Icon(Icons.expand_more, size: 18),
      ),
    );
  }
}