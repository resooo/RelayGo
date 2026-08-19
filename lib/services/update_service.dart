import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:relaygo/config/constants.dart';
import 'package:relaygo/models/app_release.dart';

/// 下载进度
class DownloadProgress {
  final int received;
  final int total; // 0 表示未知
  const DownloadProgress(this.received, this.total);

  double get ratio => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
  String get percent =>
      total <= 0 ? '--' : '${(ratio * 100).toStringAsFixed(1)}%';
}

/// 下载结果
class DownloadResult {
  final bool ok;
  final String? filePath;
  final String? error;
  final String? sha256; // 实际算出的摘要
  final int bytes;

  const DownloadResult({
    required this.ok,
    this.filePath,
    this.error,
    this.sha256,
    this.bytes = 0,
  });
}

/// 在线更新服务（应用内升级迭代通道）
///
/// 支持两种更新源：
///  - **GitHub Releases（方案一，推荐）**：配置 `githubRepo`（owner/repo）后，
///    拉取 `api.github.com/repos/{owner}/{repo}/releases/latest`。发布 Release
///    即发版、自动提供下载、全球 CDN 加速、零服务器成本；
///  - **静态 JSON 清单**：`githubRepo` 为空时回退，清单可托管在对象存储 /
///    自建服务，改 JSON 即可发版。
///
/// 设计要点：
///  - **零原生依赖**：只用 `http` + `dart:io`；
///  - **渠道**：stable 用 `/releases/latest`；beta 走列表并取最新预发布；
///  - **产物映射**：GitHub 的 assets 按文件名后缀自动归到对应平台，
///    找不到匹配时回退为 `any`；
///  - **完整性**：下载时流式累算 SHA-256，与清单比对（GitHub 无摘要时跳过）；
///  - **可测试**：`httpClient` / `currentVersion` / `platformName` /
///    `downloadDir` 全部可注入。
class UpdateService {
  final http.Client _client;
  final bool _ownsClient;

  /// 版本清单地址（静态 JSON 回退源）
  String feedUrl;

  /// GitHub 发布仓库（owner/repo），非空时走 GitHub Releases（方案一）
  String githubRepo;

  /// 更新渠道（stable / beta）
  String channel;

  /// 当前应用版本与构建号
  final String currentVersion;
  final int currentBuildNumber;

  /// 平台标识（android / ios / linux / windows / macos）
  final String platformName;

  /// 下载目录（默认系统临时目录）
  final Directory downloadDir;

  final Duration checkTimeout;
  final Duration downloadTimeout;

  UpdateService({
    http.Client? httpClient,
    String? feedUrl,
    String? githubRepo,
    String? channel,
    String? currentVersion,
    int? currentBuildNumber,
    String? platformName,
    Directory? downloadDir,
    Duration? checkTimeout,
    Duration? downloadTimeout,
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        feedUrl = feedUrl ?? Constants.defaultUpdateFeedUrl,
        githubRepo = githubRepo ?? '',
        channel = channel ?? Constants.defaultUpdateChannel,
        currentVersion = currentVersion ?? Constants.appVersion,
        currentBuildNumber = currentBuildNumber ?? Constants.appBuildNumber,
        platformName = platformName ?? detectPlatform(),
        downloadDir = downloadDir ?? Directory.systemTemp,
        checkTimeout = checkTimeout ??
            const Duration(seconds: Constants.updateCheckTimeoutSeconds),
        downloadTimeout = downloadTimeout ??
            const Duration(seconds: Constants.updateDownloadTimeoutSeconds);

  /// 最近一次检查结果（供 UI 直接读取）
  UpdateCheckResult? lastResult;

  /// 已下载待安装的包路径
  String? pendingInstallPath;

  static String detectPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'any';
  }

  // ————————————————————————————————————————————
  // 版本比较
  // ————————————————————————————————————————————

  /// 语义化版本比较：a > b 返回正数，a < b 返回负数，相等返回 0。
  ///
  /// 支持 `3.1`、`3.1.0`、`3.1.0.2`，以及 `-beta.1` 形式的预发布后缀
  /// （数字段相同时，带预发布后缀的版本视为更旧）。
  static int compareVersions(String a, String b) {
    final pa = _splitVersion(a);
    final pb = _splitVersion(b);
    final numsA = pa[0] as List<int>;
    final numsB = pb[0] as List<int>;
    final len = numsA.length > numsB.length ? numsA.length : numsB.length;
    for (var i = 0; i < len; i++) {
      final x = i < numsA.length ? numsA[i] : 0;
      final y = i < numsB.length ? numsB[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    final preA = pa[1] as String;
    final preB = pb[1] as String;
    if (preA.isEmpty && preB.isEmpty) return 0;
    if (preA.isEmpty) return 1; // 正式版 > 预发布
    if (preB.isEmpty) return -1;
    return preA.compareTo(preB);
  }

  static List<Object> _splitVersion(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    var pre = '';
    final dash = s.indexOf('-');
    if (dash >= 0) {
      pre = s.substring(dash + 1);
      s = s.substring(0, dash);
    }
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus); // 构建元数据不参与数字段比较
    final nums = s
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    return <Object>[nums, pre];
  }

  /// 远端版本是否比本地更新（版本号相同时用构建号兜底）
  bool isNewer(AppRelease release) {
    final c = compareVersions(release.version, currentVersion);
    if (c != 0) return c > 0;
    return release.buildNumber > currentBuildNumber;
  }

  // ————————————————————————————————————————————
  // 检查更新
  // ————————————————————————————————————————————

  /// 是否启用 GitHub Releases 更新源（方案一）
  bool get githubMode => githubRepo.trim().isNotEmpty;

  /// 拉取远端更新信息并与本地版本比较。
  ///
  /// `githubRepo` 非空时走 GitHub Releases API，否则回退到静态 JSON 清单。
  Future<UpdateCheckResult> checkForUpdate() async {
    if (githubMode) return _checkGithub();
    return _checkJsonManifest();
  }

  Future<UpdateCheckResult> _checkJsonManifest() async {
    if (feedUrl.trim().isEmpty) {
      return lastResult = UpdateCheckResult(
        status: UpdateStatus.failed,
        currentVersion: currentVersion,
        error: '未配置更新源地址',
      );
    }
    try {
      final resp = await _client
          .get(Uri.parse(feedUrl), headers: {
            'accept': 'application/json',
            'cache-control': 'no-cache',
          })
          .timeout(checkTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return lastResult = UpdateCheckResult(
          status: UpdateStatus.failed,
          currentVersion: currentVersion,
          error: '更新源返回 ${resp.statusCode}',
        );
      }
      final release = parseFeed(utf8.decode(resp.bodyBytes), channel);
      return _evaluate(release, errorWhenNull: '更新源内容无法解析（渠道 $channel 不存在？）');
    } catch (e) {
      return lastResult = _fail(e.toString());
    }
  }

  /// 从 GitHub Releases 拉取更新信息。
  /// stable 用 `/releases/latest`；beta 用列表取最新预发布。
  Future<UpdateCheckResult> _checkGithub() async {
    final repo = githubRepo.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final isBeta = channel == 'beta';
    final url = isBeta
        ? '${Constants.updateGithubApiBase}/$repo${Constants.updateGithubApiList}'
        : '${Constants.updateGithubApiBase}/$repo${Constants.updateGithubApiLatest}';
    try {
      final resp = await _client.get(Uri.parse(url), headers: {
        'accept': Constants.updateGithubApiAccept,
        'cache-control': 'no-cache',
      }).timeout(checkTimeout);
      if (resp.statusCode == 404) {
        return lastResult = _fail('仓库 $repo 没有 Release，请确认 owner/repo 或已发布版本');
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return lastResult = _fail('GitHub 返回 ${resp.statusCode}');
      }
      final release = isBeta
          ? parseGithubReleases(utf8.decode(resp.bodyBytes), channel: channel)
          : parseGithubReleaseBody(utf8.decode(resp.bodyBytes),
              channel: channel);
      return _evaluate(release,
          errorWhenNull: '加载 GitHub Release 失败（仓库 $repo 或渠道 $channel 无匹配版本）');
    } catch (e) {
      return lastResult = _fail(e.toString());
    }
  }

  UpdateCheckResult _fail(String error) => UpdateCheckResult(
        status: UpdateStatus.failed,
        currentVersion: currentVersion,
        error: error,
      );

  UpdateCheckResult _evaluate(AppRelease? release,
      {required String errorWhenNull}) {
    if (release == null) {
      return lastResult = UpdateCheckResult(
        status: UpdateStatus.failed,
        currentVersion: currentVersion,
        error: errorWhenNull,
      );
    }
    final below = release.minSupportedVersion.isNotEmpty &&
        compareVersions(currentVersion, release.minSupportedVersion) < 0;
    if (!isNewer(release)) {
      return lastResult = UpdateCheckResult(
        status: UpdateStatus.upToDate,
        currentVersion: currentVersion,
        release: release,
      );
    }
    return lastResult = UpdateCheckResult(
      status: UpdateStatus.available,
      currentVersion: currentVersion,
      release: release,
      belowMinSupported: below,
    );
  }

  /// 解析一个 GitHub Release 对象接口：`/releases/latest` 的响应体。
  static AppRelease? parseGithubReleaseBody(String body,
      {String channel = 'stable'}) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    return parseGithubRelease(Map<String, dynamic>.from(json),
        channel: channel);
  }

  /// 解析 GitHub Releases 列表（`/releases` 的响应体），取该渠道下最新的一条。
  /// stable 跳过预发布；beta 保留并优先最新预发布。
  static AppRelease? parseGithubReleases(String body,
      {String channel = 'stable'}) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! List) return null;
    final stableOnly = channel != 'beta';
    final list = <AppRelease>[];
    for (final item in json) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      if (m['draft'] == true) continue;
      if (stableOnly && m['prerelease'] == true) continue; // stable 跳过预发布
      list.add(parseGithubRelease(m, channel: channel));
    }
    if (list.isEmpty) return null;
    list.sort((a, b) {
      final c = compareVersions(b.version, a.version);
      if (c != 0) return c;
      return b.publishedAt.compareTo(a.publishedAt);
    });
    return list.first;
  }

  /// 把单个 GitHub Release 对象映射为 [AppRelease]。
  ///
  /// 约定：版本号取 `tag_name`（去掉前导 v）；发布说明取 `body`；
  /// assets 按文件名后缀归到对应平台；强制更新用 body 中的
  /// `[强制更新]` / `[mandatory]` / `[force]` 标记。
  static AppRelease parseGithubRelease(Map<String, dynamic> json,
      {String channel = 'stable'}) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final version = tag.replaceFirst(RegExp(r'^[vV]'), '').trim();
    final body = json['body'] as String? ?? '';
    final publishedAt = _parseGithubDate(json['published_at']);

    final artifacts = <String, ReleaseArtifact>{};
    final assets = json['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = (a['name'] as String? ?? '').trim();
        final url = (a['browser_download_url'] as String? ?? '').trim();
        if (name.isEmpty || url.isEmpty) continue;
        final platform = _platformForAsset(name);
        final existing = artifacts[platform];
        // 同平台多个产物：优先保留更大的（release 包通常比调试包大）
        final size = a['size'] as int? ?? 0;
        if (existing == null || size > existing.size) {
          artifacts[platform] = ReleaseArtifact(
            platform: platform,
            url: url,
            size: size,
          );
        }
      }
    }

    return AppRelease(
      channel: channel,
      version: version.isEmpty ? tag : version,
      releaseNotes: body,
      publishedAt: publishedAt,
      mandatory: _containsMandatoryMarker(body),
      artifacts: artifacts,
    );
  }

  static int _parseGithubDate(Object? raw) {
    if (raw is! String) return 0;
    return DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
  }

  static bool _containsMandatoryMarker(String body) {
    final b = body.toLowerCase();
    return b.contains('强制更新') ||
        b.contains('[mandatory]') ||
        b.contains('[force]') ||
        b.contains('[重要][必须更新]');
  }

  /// 按 GitHub asset 文件名猜测目标平台。
  static String _platformForAsset(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.apk')) return 'android';
    if (n.endsWith('.ipa')) return 'ios';
    if (n.contains('macos') || n.contains('darwin') || n.endsWith('.dmg') ||
        n.endsWith('.pkg')) {
      return 'macos';
    }
    if (n.contains('windows') || n.endsWith('.msix') || n.endsWith('.exe')) {
      return 'windows';
    }
    if (n.contains('linux') || n.endsWith('.tar.gz') || n.endsWith('.tgz') ||
        n.endsWith('.appimage') || n.endsWith('.deb')) {
      return 'linux';
    }
    return 'any'; // 无法识别目标，挂到 any 由 artifactFor 回退
  }

  /// 解析清单文本。支持三种形态：
  ///  1. 单渠道裸对象 `{"version": ...}`
  ///  2. 多渠道包裹 `{"stable": {...}, "beta": {...}}`
  ///  3. 版本数组 `[{...}, {...}]`（取该渠道下最新的一条）
  static AppRelease? parseFeed(String body, String channel) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }

    if (json is List) {
      final list = json
          .whereType<Map>()
          .map((m) => AppRelease.fromJson(Map<String, dynamic>.from(m)))
          .where((r) => r.channel == channel || channel.isEmpty)
          .toList();
      if (list.isEmpty) return null;
      list.sort((a, b) => compareVersions(b.version, a.version));
      return list.first;
    }

    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);

    // 形态 1：本身就带 version 字段
    if (map.containsKey('version')) {
      return AppRelease.fromJson(map);
    }

    // 形态 2：按渠道取
    final picked = map[channel] ?? map[Constants.defaultUpdateChannel];
    if (picked is Map) {
      final m = Map<String, dynamic>.from(picked);
      m.putIfAbsent('channel', () => channel);
      return AppRelease.fromJson(m);
    }
    return null;
  }

  // ————————————————————————————————————————————
  // 下载与校验
  // ————————————————————————————————————————————

  /// 下载指定发布的安装包并做 SHA-256 校验。
  ///
  /// 商店链接类产物（iOS 等）不做下载，直接返回失败并提示由 UI 跳转。
  Future<DownloadResult> download(
    AppRelease release, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    final artifact = release.artifactFor(platformName);
    if (artifact == null || artifact.url.isEmpty) {
      return DownloadResult(
        ok: false,
        error: '该版本没有提供 $platformName 平台的安装包',
      );
    }
    if (artifact.isStoreLink) {
      return DownloadResult(
        ok: false,
        error: '该平台需前往应用商店更新：${artifact.url}',
      );
    }

    final fileName = _fileNameFor(release, artifact);
    final target = File('${downloadDir.path}${Platform.pathSeparator}$fileName');
    IOSink? sink;
    try {
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      if (await target.exists()) await target.delete();

      final req = http.Request('GET', Uri.parse(artifact.url));
      final resp = await _client.send(req).timeout(downloadTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return DownloadResult(ok: false, error: '下载失败：HTTP ${resp.statusCode}');
      }

      final total = resp.contentLength ?? artifact.size;
      var received = 0;
      final digestSink = _DigestAccumulator();
      final hasher = sha256.startChunkedConversion(digestSink);
      sink = target.openWrite();

      await for (final chunk in resp.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received, total));
      }
      hasher.close();
      await sink.flush();
      await sink.close();
      sink = null;

      final actual = digestSink.digest!.toString(); // Digest.toString() 即 hex
      if (artifact.sha256.isNotEmpty && actual != artifact.sha256) {
        await target.delete();
        return DownloadResult(
          ok: false,
          error: '完整性校验失败：期望 ${artifact.sha256}，实际 $actual',
          sha256: actual,
          bytes: received,
        );
      }

      pendingInstallPath = target.path;
      return DownloadResult(
        ok: true,
        filePath: target.path,
        sha256: actual,
        bytes: received,
      );
    } catch (e) {
      try {
        await sink?.close();
        if (await target.exists()) await target.delete();
      } catch (_) {
        // 清理失败不覆盖原始错误
      }
      return DownloadResult(ok: false, error: e.toString());
    }
  }

  String _fileNameFor(AppRelease release, ReleaseArtifact artifact) {
    final uriPath = Uri.parse(artifact.url).path;
    final last = uriPath.split('/').where((e) => e.isNotEmpty).toList();
    final ext = last.isEmpty ? '' : _extOf(last.last);
    return 'relaygo-${release.version}-$platformName$ext';
  }

  String _extOf(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0) return '';
    final ext = name.substring(i);
    // 处理 .tar.gz 这类双后缀
    final base = name.substring(0, i);
    if (base.endsWith('.tar')) return '.tar$ext';
    return ext;
  }

  /// 计算本地文件的 SHA-256（用于校验已下载包）
  static Future<String> fileSha256(File file) async {
    final digestSink = _DigestAccumulator();
    final hasher = sha256.startChunkedConversion(digestSink);
    await for (final chunk in file.openRead()) {
      hasher.add(chunk);
    }
    hasher.close();
    return digestSink.digest!.toString();
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

/// 收集 chunked SHA-256 的最终摘要
class _DigestAccumulator implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
