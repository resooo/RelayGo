import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/services/cache_manager.dart';
import 'package:relaygo/services/report_service.dart';
import 'package:relaygo/utils/formatters.dart';
import 'package:relaygo/widgets/chart_widgets.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 统计报表页（需求 2.2.7 / Phase 3）
///
/// 基于 [ReportService] 生成「日 / 周 / 月」报表：概览、每日趋势、
/// Top 模型 / Key / 提供商、缓存与限流观测，并支持导出
/// JSON / CSV / Markdown（复制到剪贴板，便于粘贴到文档或 IM）。
class ReportScreen extends StatefulWidget {
  const ReportScreen({Key? key}) : super(key: key);

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ReportPeriod _period = ReportPeriod.day;
  late UsageReport _report;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _generate();
  }

  void _generate() {
    final app = Provider.of<AppState>(context, listen: false);
    _report = app.proxy.reportService.generate(period: _period);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.instance;
    final s = _report.stats;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.t('统计报表')),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: t.t('导出 JSON'),
            onPressed: () => _export(context, 'json'),
          ),
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: t.t('导出 CSV'),
            onPressed: () => _export(context, 'csv'),
          ),
          IconButton(
            icon: const Icon(Icons.article),
            tooltip: t.t('导出 Markdown'),
            onPressed: () => _export(context, 'md'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: ToggleButtons(
                  isSelected: [
                    _period == ReportPeriod.day,
                    _period == ReportPeriod.week,
                    _period == ReportPeriod.month,
                  ],
                  onPressed: (i) {
                    setState(() {
                      _period = const [
                        ReportPeriod.day,
                        ReportPeriod.week,
                        ReportPeriod.month
                      ][i];
                      _generate();
                    });
                  },
                  children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Text(L10n.tr('日报'))),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Text(L10n.tr('周报'))),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Text(L10n.tr('月报'))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              _stat(L10n.tr('请求数'), '${s.total}'),
              _stat(L10n.tr('错误数'), '${s.errors}'),
              _stat(L10n.tr('错误率'),
                  '${(s.errorRate * 100).toStringAsFixed(1)}%'),
              _stat(L10n.tr('Token'), Formatters.formatNumber(s.totalTokens)),
              _stat(L10n.tr('平均耗时'), Formatters.formatDuration(s.avgDurationMs)),
              _stat(L10n.tr('P95'), Formatters.formatDuration(s.p95DurationMs)),
              _stat(L10n.tr('缓存命中'), '${_report.cachedRequests}'),
              _stat(L10n.tr('缓存命中率'),
                  '${(_report.cacheHitRate * 100).toStringAsFixed(1)}%'),
              _stat(L10n.tr('环比请求'),
                  _pct(_report.requestsDelta.changeRate)),
            ],
          ),
          const SizedBox(height: 14),
          _chartCard(t.t('每日请求趋势'),
              SimpleBarChart(data: _dailyMap())),
          const SizedBox(height: 12),
          _chartCard(t.t('每日错误趋势'),
              SimpleBarChart(
                  data: _dailyMap(errors: true), color: Colors.red)),
          const SizedBox(height: 12),
          _rankCard(t.t('Top 模型'), _report.topModels),
          const SizedBox(height: 12),
          _rankCard(t.t('Top Key'), _report.topKeys),
          const SizedBox(height: 12),
          _rankCard(t.t('Top 提供商'), _report.topProviders),
          const SizedBox(height: 12),
          if (_report.rateLimitedByDimension.isNotEmpty)
            _rateLimitCard(t, _report.rateLimitedByDimension),
          if (_report.cacheStats != null)
            _cacheCard(t, _report.cacheStats!),
        ],
      ),
    );
  }

  Map<String, int> _dailyMap({bool errors = false}) {
    final out = <String, int>{};
    for (final d in _report.daily) {
      out[d.date.substring(5)] = errors ? d.errors : d.requests;
    }
    return out;
  }

  Widget _stat(String label, String value) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      );

  Widget _chartCard(String title, Widget chart) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              chart,
            ],
          ),
        ),
      );

  Widget _rankCard(String title, List<RankedItem> items) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (items.isEmpty)
                Text(L10n.tr('（暂无数据）'),
                    style: const TextStyle(color: Colors.grey))
              else
                ...items.map((e) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.name.isEmpty ? L10n.tr('(未知)') : e.name),
                      trailing: Text(L10n.fmt('{count} 次 · {tokens} tok',
                          {
                            'count': '${e.count}',
                            'tokens': Formatters.formatNumber(e.tokens)
                          })),
                    )),
            ],
          ),
        ),
      );

  Widget _rateLimitCard(L10n t, Map<String, int> data) => Card(
        color: Colors.orange.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.t('限流触发'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...data.entries.map((e) => Text(L10n.fmt('{key}：{value} 次',
                  {'key': e.key, 'value': '${e.value}'}))),
            ],
          ),
        ),
      );

  Widget _cacheCard(L10n t, CacheStats stats) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.t('缓存统计'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(L10n.fmt(
                  '命中 {hits} / 未命中 {misses} · 命中率 {rate}% · 条目 {entries} · {kb} KB',
                  {
                    'hits': '${stats.hits}',
                    'misses': '${stats.misses}',
                    'rate': (stats.hitRate * 100).toStringAsFixed(1),
                    'entries': '${stats.entries}',
                    'kb': (stats.bytes / 1024).toStringAsFixed(1),
                  })),
            ],
          ),
        ),
      );

  Future<void> _export(BuildContext context, String kind) async {
    final t = L10n.instance;
    final text = kind == 'json'
        ? ReportService.toJsonString(_report)
        : kind == 'csv'
            ? ReportService.toCsv(_report)
            : ReportService.toMarkdown(_report);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${t.t('已复制到剪贴板')}（${kind.toUpperCase()}）')));
  }

  String _pct(double v) =>
      '${(v * 100).toStringAsFixed(1)}%';
}
