import 'package:flutter/material.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/l10n/app_strings.dart';
import 'package:relaygo/models/model_sync_exception.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/services/model_sync_service.dart';

/// 模型同步进度对话框
///
/// - [providers] 为 null/空时同步「全部」active 服务商；
/// - 传入单个 provider 时仅同步该服务商。
/// 支持实时进度、取消、完成后结果摘要。
class SyncProgressDialog extends StatefulWidget {
  final AppState app;
  final List<String>? providers;

  const SyncProgressDialog({Key? key, required this.app, this.providers})
      : super(key: key);

  @override
  State<SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<SyncProgressDialog> {
  final Map<String, SyncProgress> _progress = {};
  bool _syncing = true;
  bool _cancelled = false;
  SyncResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final ps = widget.providers;
    late SyncResult result;
    if (ps != null && ps.isNotEmpty) {
      final results = <String, ProviderSyncResult>{};
      for (final p in ps) {
        if (_cancelled) break;
        if (!mounted) return;
        setState(() => _progress[p] = SyncProgress(
            p, SyncStatus.syncing, L10n.fmt('正在同步 {p} 的模型列表...', {'p': p})));
        try {
          final r = await widget.app
              .syncProviderModels(p, isCancelled: () => _cancelled);
          results[p] = r;
          if (!mounted) return;
          setState(() => _progress[p] = SyncProgress(
              p,
              SyncStatus.completed,
              L10n.fmt('{p} 同步完成，共 {n} 个模型',
                  {'p': p, 'n': '${r.models.length}'})));
        } catch (e) {
          results[p] = ProviderSyncResult(
              provider: p,
              success: false,
              error: ModelSyncException.friendly(e));
          if (!mounted) return;
          setState(() => _progress[p] = SyncProgress(
              p,
              SyncStatus.failed,
              L10n.fmt('{p} 同步失败：{err}',
                  {'p': p, 'err': '${results[p]!.error}'})));
        }
      }
      result = SyncResult(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        providerResults: results,
        totalModels: results.values.fold(0, (s, r) => s + r.models.length),
      );
    } else {
      result = await widget.app.syncModels(
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress[p.provider] = p);
        },
        isCancelled: () => _cancelled,
      );
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _result = result;
    });
  }

  void _cancel() => setState(() => _cancelled = true);

  @override
  Widget build(BuildContext context) {
    final total = widget.providers != null && widget.providers!.isNotEmpty
        ? widget.providers!.length
        : widget.app.modelSync.activeProviderIds.length;
    final done = _progress.values
        .where((p) => p.status != SyncStatus.syncing)
        .length;
    final overall = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;

    return AlertDialog(
      title: Text(L10n.tr('同步模型')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: _syncing ? overall : 1.0),
            const SizedBox(height: 12),
            Text(_syncing
                ? L10n.fmt('正在同步 {done}/{total} 个服务商',
                    {'done': '$done', 'total': '$total'})
                : L10n.tr('同步完成')),
            const SizedBox(height: 12),
            ..._progress.values.map((p) => ListTile(
                  dense: true,
                  leading: _statusIcon(p.status),
                  title: Text(widget.app.getProvider(p.provider)?.name ??
                      ProviderTypeX.fromString(p.provider).displayName),
                  subtitle: Text(p.message),
                )),
            if (!_syncing && _result != null) ..._summary(_result!),
          ],
        ),
      ),
      actions: [
        if (_syncing)
          TextButton(onPressed: _cancel, child: Text(L10n.tr('取消')))
        else
          TextButton(
            onPressed: () => Navigator.pop(context, _result),
            child: Text(L10n.tr('完成')),
          ),
      ],
    );
  }

  Widget _statusIcon(SyncStatus s) {
    switch (s) {
      case SyncStatus.syncing:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SyncStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
      case SyncStatus.failed:
        return const Icon(Icons.error, color: Colors.red, size: 20);
    }
  }

  List<Widget> _summary(SyncResult r) {
    return [
      const Divider(),
      Text(
          L10n.fmt('成功 {ok} 个服务商，失败 {fail} 个',
              {'ok': '${r.successCount}', 'fail': '${r.failedCount}'}),
          style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(L10n.fmt('新增 {n} · 更新 {u} · 下线 {r} · 共 {t} 个模型', {
        'n': '${r.newCount}',
        'u': '${r.updatedCount}',
        'r': '${r.removedCount}',
        't': '${r.totalModels}',
      })),
    ];
  }
}
