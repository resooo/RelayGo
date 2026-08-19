import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:relaygo/app.dart';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/l10n/app_strings.dart';
import 'package:relaygo/models/free_provider.dart';

/// 免费 API 推荐页（Free LLM API Hub）
///
/// 数据来源：Free LLM API Hub v2.9.0（providers.json）
/// 策略：进入页面时检查本地缓存，超过 24 小时自动后台刷新；网络失败展示缓存。
class FreeApiScreen extends StatefulWidget {
  const FreeApiScreen({Key? key}) : super(key: key);

  @override
  State<FreeApiScreen> createState() => _FreeApiScreenState();
}

class _FreeApiScreenState extends State<FreeApiScreen> {
  FreeApiDataset? _dataset;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = Provider.of<AppState>(context, listen: false);
    final service = app.freeApiService;
    // 先展示缓存（若有），再后台刷新
    final cached = service.cached;
    if (cached != null) {
      setState(() {
        _dataset = cached;
        _loading = false;
      });
    }
    final fresh = await service.ensureFresh();
    if (!mounted) return;
    setState(() {
      _dataset = fresh;
      _loading = false;
      _error = service.lastRefresh?.ok == false ? service.lastRefresh?.error : null;
    });
  }

  Future<void> _refresh() async {
    final app = Provider.of<AppState>(context, listen: false);
    setState(() => _loading = true);
    final ok = await app.freeApiService.refresh();
    if (!mounted) return;
    setState(() {
      _dataset = app.freeApiService.cached;
      _loading = false;
      _error = ok ? null : app.freeApiService.lastRefresh?.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dataset = _dataset;
    final providers = dataset?.providers ?? const <FreeProvider>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr('免费 API 推荐')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: L10n.tr('刷新'),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _loading && providers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : providers.isEmpty
              ? _buildEmpty()
              : _buildList(dataset!, providers),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(L10n.tr('暂无数据'), style: const TextStyle(fontSize: 16)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                L10n.fmt('加载失败：{err}', {'err': '$_error'}),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: Text(L10n.tr('重试')),
          ),
        ],
      ),
    );
  }

  Widget _buildList(FreeApiDataset dataset, List<FreeProvider> providers) {
    final cachedAt = Provider.of<AppState>(context).freeApiService.cachedAt;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSourceCard(dataset, cachedAt),
          const SizedBox(height: 8),
          for (final p in providers) _buildProviderTile(p),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              L10n.tr('免责声明：免费政策可能随时变动，使用前请务必点击「官方文档」进行最终确认。'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard(FreeApiDataset dataset, int? cachedAt) {
    final updated = cachedAt == null
        ? L10n.tr('未知')
        : _formatTime(cachedAt);
    return Card(
      color: Colors.indigo.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.indigo, size: 18),
                const SizedBox(width: 6),
                Text(
                  L10n.fmt('数据来源：{src}', {'src': Constants.freeApiSourceName}),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              L10n.fmt('数据版本：{v}',
                      {'v': dataset.version.isNotEmpty ? dataset.version : Constants.freeApiVersion}) +
                  '　' +
                  L10n.fmt('生成日期：{d}',
                      {'d': dataset.generated.isNotEmpty ? dataset.generated : L10n.tr('未知')}) +
                  '　' +
                  L10n.fmt('本地更新：{t}', {'t': updated}),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _buildProviderTile(FreeProvider p) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: p.verified
              ? Colors.green.shade100
              : Colors.orange.shade100,
          child: Text(
            p.flagEmoji,
            style: const TextStyle(fontSize: 22),
          ),
        ),
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.bestFor != null && p.bestFor!.isNotEmpty)
              Text(
                p.bestFor!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 6,
              children: [
                _chip(p.categoryLabel, Colors.indigo),
                _chip(p.freeTypeLabel, Colors.teal),
                if (p.commercialOk == true)
                  _chip(L10n.tr('允许商用'), Colors.green)
                else if (p.commercialOk == false)
                  _chip(L10n.tr('禁止商用'), Colors.red),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FreeProviderDetailScreen(provider: p)),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

/// 提供商详情页（完整中文化展示）
class FreeProviderDetailScreen extends StatelessWidget {
  final FreeProvider provider;
  const FreeProviderDetailScreen({Key? key, required this.provider})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = provider;
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 头部：名称 + 国旗 + 标签
          Row(
            children: [
              Text(p.flagEmoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _detailChip(L10n.fmt('免费类型：{v}', {'v': p.categoryLabel}), Colors.indigo),
              _detailChip(L10n.fmt('免费模式：{v}', {'v': p.freeTypeLabel}), Colors.teal),
              _detailChip(L10n.fmt('已验证：{v}', {'v': p.verifiedLabel}),
                  p.verified ? Colors.green : Colors.orange),
            ],
          ),
          const SizedBox(height: 16),

          // 最佳用途（保留原文）
          if (p.bestFor != null && p.bestFor!.isNotEmpty)
            _section(context, L10n.tr('最佳用途'), p.bestFor!, highlight: true),
          if (p.freeTier != null && p.freeTier!.isNotEmpty)
            _section(context, L10n.tr('免费额度详情'), p.freeTier!, highlight: true),
          if (p.rateLimits != null && p.rateLimits!.isNotEmpty)
            _section(context, L10n.tr('速率限制'), p.rateLimits!),

          // 限制条件
          _section(context, L10n.tr('限制条件'),
              L10n.fmt('需要手机验证：{v}',
                      {'v': FreeProvider.boolLabel(p.phoneRequired)}) +
                  '\n' +
                  L10n.fmt('需要信用卡：{v}',
                      {'v': FreeProvider.boolLabel(p.cardRequired)}) +
                  '\n' +
                  L10n.fmt('允许商用：{v}',
                      {'v': FreeProvider.boolLabel(p.commercialOk)}) +
                  '\n' +
                  L10n.fmt('OpenAI 接口兼容：{v}',
                      {'v': FreeProvider.boolLabel(p.openaiCompatible)})),

          // 功能与模型
          _section(context, L10n.tr('支持模态'), p.modalitiesLabel),
          _section(context, L10n.tr('免费模型列表'), p.modelsLabel),

          // 技术集成
          _section(context, L10n.tr('OpenAI 兼容接口地址'),
              p.openaiBaseUrl?.isNotEmpty == true ? p.openaiBaseUrl! : L10n.tr('不适用')),
          _section(context, L10n.tr('环境变量密钥名'),
              p.envKey?.isNotEmpty == true ? p.envKey! : L10n.tr('未说明')),

          // 元信息
          _section(context, L10n.tr('额度过期时间'), p.expiresLabel),
          if (p.lastVerified != null && p.lastVerified!.isNotEmpty)
            _section(context, L10n.tr('最近验证日期'), p.lastVerified!),
          if (p.notes != null && p.notes!.isNotEmpty)
            _section(context, L10n.tr('重要注意事项'), p.notes!),

          const SizedBox(height: 12),

          // 官方文档按钮
          if (p.docsUrl != null && p.docsUrl!.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(L10n.tr('查看官方文档')),
                onPressed: () => _openDocs(context, p.docsUrl!),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            L10n.tr('免责声明：免费政策可能随时变动，使用前请务必点击「官方文档」进行最终确认。'),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _detailChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  Widget _section(BuildContext context, String title, String content,
      {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: highlight
                  ? Colors.indigo.withOpacity(0.06)
                  : Colors.grey.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: highlight
                  ? Border.all(color: Colors.indigo.withOpacity(0.3))
                  : null,
            ),
            child: Text(content,
                style: TextStyle(
                  fontSize: 13,
                  color: highlight ? Colors.indigo.shade900 : Colors.black87,
                )),
          ),
        ],
      ),
    );
  }

  Future<void> _openDocs(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger?.showSnackBar(SnackBar(content: Text(L10n.tr('无法打开链接'))));
      }
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(L10n.tr('无法打开链接'))));
    }
  }
}
