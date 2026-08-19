import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/app_release.dart';
import 'package:relaygo/services/update_service.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 关于与更新页（需求：在线更新接口 / Phase 3）
///
/// - 展示当前版本、构建号、运行平台；
/// - 支持手动「检查更新」并展示发布说明；
/// - 下载安装包时实时显示进度，并对 iOS 等商店链接给出跳转提示；
/// - 升级迭代只需改远端静态 JSON 清单即可，无需发版 App。
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({Key? key}) : super(key: key);

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String _progressText = '';
  UpdateCheckResult? _result;
  String? _downloadError;
  String? _downloadedPath;

  Future<void> _check(AppState app) async {
    setState(() {
      _checking = true;
      _result = null;
      _downloadError = null;
      _downloadedPath = null;
    });
    final r = await app.checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = r;
    });
  }

  Future<void> _download(AppState app, AppRelease release) async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _progressText = L10n.tr('正在下载');
      _downloadError = null;
      _downloadedPath = null;
    });
    final res = await app.updateService.download(
      release,
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _progress = p.ratio;
          _progressText = p.percent;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _downloading = false;
      if (res.ok) {
        _downloadedPath = res.filePath;
      } else {
        _downloadError = res.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);
    final t = L10n.instance;
    final platform = UpdateService.detectPlatform();
    final release = _result?.release;

    return Scaffold(
      appBar: AppBar(title: Text(t.t('关于与更新'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.auto_awesome, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(Constants.appName,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _kv(t.t('当前版本'),
                      '${Constants.appVersion}+${Constants.appBuildNumber}'),
                  _kv(t.t('运行平台'), platform),
                  _kv(t.t('更新渠道'),
                      app.settings.updateChannel == 'beta' ? 'Beta' : 'Stable'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            icon: _checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update),
            label: Text(_checking ? t.t('正在检查') : t.t('检查更新')),
            onPressed: _checking ? null : () => _check(app),
          ),
          const SizedBox(height: 16),

          if (_result != null) _buildResult(t, release, app),
        ],
      ),
    );
  }

  Widget _buildResult(L10n t, AppRelease? release, AppState app) {
    final r = _result!;
    if (r.status == UpdateStatus.failed) {
      return Card(
        color: Colors.red.shade50,
        child: ListTile(
          leading: const Icon(Icons.error, color: Colors.red),
          title: Text(t.t('检查更新失败')),
          subtitle: Text(r.error ?? t.t('未知')),
        ),
      );
    }
    if (!r.hasUpdate) {
      return Card(
        color: Colors.green.shade50,
        child: ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: Text(t.t('已是最新')),
          subtitle: Text('${t.t('最新版本')}：${release?.displayVersion ?? ''}'),
        ),
      );
    }

    // 有可用更新
    final artifact = release!.artifactFor(UpdateService.detectPlatform());
    final isStore = artifact?.isStoreLink ?? false;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.new_releases,
                    color: r.mustUpdate ? Colors.red : Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t.t('发现新版本'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                if (r.mustUpdate)
                  Chip(
                    label: Text(t.t('强制更新')),
                    backgroundColor: Colors.red.shade100,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _kv(t.t('最新版本'), release.displayVersion),
            const SizedBox(height: 8),
            Text(t.t('发布说明'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(release.releaseNotes.isEmpty
                ? t.t('（无）')
                : release.releaseNotes),
            const SizedBox(height: 16),

            // 下载区
            if (isStore)
              _storeHint(t, artifact!.url)
            else if (_downloading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 6),
                  Text('${t.t('正在下载')} $_progressText'),
                ],
              )
            else if (_downloadError != null)
              Text('${t.t('下载失败')}：$_downloadError',
                  style: const TextStyle(color: Colors.red))
            else if (_downloadedPath != null)
              Text('${t.t('已下载，可安装')}：$_downloadedPath')
            else if (artifact == null || artifact.url.isEmpty)
              Text(t.t('该版本没有提供当前平台的安装包'),
                  style: const TextStyle(color: Colors.orange))
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text(t.t('下载更新')),
                  onPressed: () => _download(app, release),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _storeHint(L10n t, String url) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.open_in_new, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(child: Text(t.t('该平台需前往应用商店更新'))),
            TextButton(
              onPressed: () {
                // 平台商店链接交由系统处理（此处仅提示）
              },
              child: Text(url),
            ),
          ],
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(k, style: const TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );
}
