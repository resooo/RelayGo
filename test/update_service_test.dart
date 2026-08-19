import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:relaygo/models/app_release.dart';
import 'package:relaygo/services/update_service.dart';

/// 极简假 http client：按 URL 返回预设响应体
class _FakeClient extends http.BaseClient {
  final Map<String, String> bodies;
  _FakeClient(this.bodies);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = bodies[request.url.toString()] ?? 'hello';
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      contentLength: bytes.length,
      request: request,
    );
  }
}

/// "hello" 的 SHA-256
const String _sha = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
const String _wrong = '0000000000000000000000000000000000000000000000000000000000000000';

void main() {
  group('版本比较', () {
    test('语义化版本与构建号', () {
      expect(UpdateService.compareVersions('3.1.0', '3.0.0'), greaterThan(0));
      expect(UpdateService.compareVersions('3.1.0', '3.1.0'), 0);
      expect(UpdateService.compareVersions('2.0.0', '3.0.0'), lessThan(0));
      expect(UpdateService.compareVersions('3.1.0', '3.1'), 0); // 缺省补 0
      // 正式版 > 预发布
      expect(UpdateService.compareVersions('3.1.0', '3.1.0-beta.1'),
          greaterThan(0));
    });

    test('isNewer 综合构建号', () {
      final svc = UpdateService(currentVersion: '3.0.0', currentBuildNumber: 3);
      expect(
          svc.isNewer(const AppRelease(version: '3.0.0', buildNumber: 4)),
          isTrue);
      expect(
          svc.isNewer(const AppRelease(version: '3.1.0', buildNumber: 0)),
          isTrue);
      expect(
          svc.isNewer(const AppRelease(version: '3.0.0', buildNumber: 3)),
          isFalse);
    });
  });

  group('清单解析 parseFeed', () {
    test('单渠道裸对象', () {
      final r = UpdateService.parseFeed(
          '{"version":"3.1.0","build_number":4}', 'stable');
      expect(r, isNotNull);
      expect(r!.version, '3.1.0');
      expect(r.buildNumber, 4);
    });

    test('多渠道包裹按渠道取', () {
      const body =
          '{"stable":{"version":"3.0.0"},"beta":{"version":"3.2.0-beta.1"}}';
      final stable = UpdateService.parseFeed(body, 'stable');
      final beta = UpdateService.parseFeed(body, 'beta');
      expect(stable!.version, '3.0.0');
      expect(beta!.version, '3.2.0-beta.1');
    });

    test('版本数组取该渠道最新', () {
      const body =
          '[{"version":"3.0.0","channel":"stable"},{"version":"3.1.0","channel":"stable"}]';
      final r = UpdateService.parseFeed(body, 'stable');
      expect(r!.version, '3.1.0');
    });

    test('无法解析返回 null', () {
      expect(UpdateService.parseFeed('not json', 'stable'), isNull);
    });

    test('简写产物字符串', () {
      final r = UpdateService.parseFeed(
          '{"version":"3.1.0","artifacts":{"linux":"https://x/a.tar.gz"}}',
          'stable');
      expect(r!.artifacts['linux']!.url, 'https://x/a.tar.gz');
    });
  });

  group('GitHub Releases 解析（方案一）', () {
    const githubRelease = '''
    {
      "tag_name": "v3.1.0",
      "body": "[强制更新] 修复若干问题",
      "published_at": "2026-08-01T00:00:00Z",
      "draft": false,
      "prerelease": false,
      "assets": [
        {"name": "RelayGo-v3.1.0.apk", "browser_download_url": "https://x/app.apk", "size": 24117248},
        {"name": "RelayGo-linux.tar.gz", "browser_download_url": "https://x/linux.tar.gz", "size": 1048576}
      ]
    }
    ''';

    test('映射对象到 AppRelease', () {
      final r = UpdateService.parseGithubReleaseBody(githubRelease);
      expect(r, isNotNull);
      expect(r!.version, '3.1.0');
      expect(r.channel, 'stable');
      expect(r.mandatory, isTrue);
      expect(r.publishedAt, greaterThan(0));
      // .apk 归到 android；.tar.gz 归到 linux
      expect(r.artifactFor('android')!.url, 'https://x/app.apk');
      expect(r.artifactFor('linux')!.url, 'https://x/linux.tar.gz');
    });

    test('列表取最新；stable 跳过预发布', () {
      const list = '''
      [
        {"tag_name": "v3.0.0", "published_at": "2026-07-01T00:00:00Z", "draft": false, "prerelease": false, "assets": []},
        {"tag_name": "v4.0.0-beta.1", "published_at": "2026-07-20T00:00:00Z", "draft": false, "prerelease": true, "assets": []}
      ]
      ''';
      final stable = UpdateService.parseGithubReleases(list, channel: 'stable');
      expect(stable!.version, '3.0.0'); // beta 被跳过
      final beta =
          UpdateService.parseGithubReleases(list, channel: 'beta');
      expect(beta!.version, '4.0.0-beta.1');
    });

    test('draft 被忽略', () {
      const list = '''
      [{"tag_name": "v9.0.0", "draft": true, "prerelease": false, "assets": []}]
      ''';
      expect(UpdateService.parseGithubReleases(list), isNull);
    });

    test('checkForUpdate 走 GitHub API', () async {
      final svc = UpdateService(
        currentVersion: '3.0.0',
        currentBuildNumber: 3,
        githubRepo: 'owner/relaygo',
        channel: 'stable',
        httpClient: _FakeClient({
          'https://api.github.com/repos/owner/relaygo/releases/latest':
              githubRelease,
        }),
      );
      final r = await svc.checkForUpdate();
      expect(r.hasUpdate, isTrue);
      expect(r.release!.version, '3.1.0');
    });

    test('未配置 repo 时回退静态清单', () async {
      final svc = UpdateService(
        currentVersion: '3.0.0',
        currentBuildNumber: 3,
        githubRepo: '',
        feedUrl: 'http://feed/latest.json',
        httpClient: _FakeClient(
            {'http://feed/latest.json': '{"version":"1.0.0","build_number":1}'}),
      );
      final r = await svc.checkForUpdate();
      expect(r.status.name, 'upToDate');
    });
  });

  group('下载与校验', () {
    test('商店链接直接失败，不下载', () async {
      final svc = UpdateService(
        platformName: 'ios',
        downloadDir: Directory.systemTemp,
      );
      const release = AppRelease(
        version: '3.1.0',
        artifacts: {
          'ios': ReleaseArtifact(
            platform: 'ios', url: 'https://apps.apple.com/app/id123'),
        },
      );
      final res = await svc.download(release);
      expect(res.ok, isFalse);
      expect(res.error, contains('应用商店'));
    });

    test('SHA-256 校验通过', () async {
      final dir = Directory.systemTemp.createTempSync('upd');
      final svc = UpdateService(
        platformName: 'linux',
        downloadDir: dir,
        httpClient: _FakeClient({'http://dl/a': 'hello'}),
      );
      const release = AppRelease(
        version: '3.1.0',
        artifacts: {
          'linux': ReleaseArtifact(
              platform: 'linux', url: 'http://dl/a', sha256: _sha),
        },
      );
      final res = await svc.download(release);
      expect(res.ok, isTrue);
      expect(res.sha256, _sha);
      expect(svc.pendingInstallPath, isNotNull);
      await dir.delete(recursive: true);
    });

    test('SHA-256 不匹配拒绝并删除临时文件', () async {
      final dir = Directory.systemTemp.createTempSync('upd2');
      final svc = UpdateService(
        platformName: 'linux',
        downloadDir: dir,
        httpClient: _FakeClient({'http://dl/b': 'hello'}),
      );
      const release = AppRelease(
        version: '3.1.0',
        artifacts: {
          'linux': ReleaseArtifact(
              platform: 'linux', url: 'http://dl/b', sha256: _wrong),
        },
      );
      final res = await svc.download(release);
      expect(res.ok, isFalse);
      expect(res.error, contains('完整性校验失败'));
      await dir.delete(recursive: true);
    });

    test('fileSha256 计算正确', () async {
      final f = File('${Directory.systemTemp.path}/sha_test.txt')
        ..writeAsStringSync('hello');
      final sha = await UpdateService.fileSha256(f);
      expect(sha, _sha);
      await f.delete();
    });
  });

  group('checkForUpdate 端到端（假 client）', () {
    test('本地已是最新', () async {
      const body = '{"version":"1.0.0","build_number":1}';
      final svc = UpdateService(
        currentVersion: '3.0.0',
        currentBuildNumber: 3,
        feedUrl: 'http://feed/latest.json',
        httpClient: _FakeClient({'http://feed/latest.json': body}),
      );
      final r = await svc.checkForUpdate();
      expect(r.status.name, 'upToDate');
      expect(r.hasUpdate, isFalse);
    });

    test('发现新版本', () async {
      const body = '{"version":"9.9.9","build_number":99}';
      final svc = UpdateService(
        currentVersion: '3.0.0',
        currentBuildNumber: 3,
        feedUrl: 'http://feed/latest.json',
        httpClient: _FakeClient({'http://feed/latest.json': body}),
      );
      final r = await svc.checkForUpdate();
      expect(r.hasUpdate, isTrue);
      expect(r.release!.version, '9.9.9');
    });
  });
}
