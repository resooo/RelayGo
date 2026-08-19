/// 应用版本（在线更新清单中的一条发布记录）
///
/// 远端清单为静态 JSON，可托管在对象存储 / GitHub Release / 自建 HTTP 服务，
/// 形如：
/// ```json
/// {
///   "channel": "stable",
///   "version": "3.1.0",
///   "build_number": 4,
///   "release_notes": "修复若干问题",
///   "published_at": 1755316800000,
///   "mandatory": false,
///   "min_supported_version": "2.0.0",
///   "artifacts": {
///     "android": {"url": "https://.../app-3.1.0.apk", "sha256": "ab..", "size": 24117248},
///     "linux":   {"url": "https://.../linux-3.1.0.tar.gz", "sha256": "cd.."},
///     "ios":     {"url": "https://apps.apple.com/app/id000000"}
///   }
/// }
/// ```
/// 也支持 `{"stable": {...}, "beta": {...}}` 的多渠道包裹形式。
class ReleaseArtifact {
  final String platform; // android / ios / linux / windows / macos
  final String url;
  final String sha256; // 可为空串（跳过校验）
  final int size; // 字节，0 表示未知

  const ReleaseArtifact({
    required this.platform,
    required this.url,
    this.sha256 = '',
    this.size = 0,
  });

  /// 是否为跳转型产物（应用商店链接，不能直接下载安装）
  bool get isStoreLink =>
      url.contains('apps.apple.com') ||
      url.contains('play.google.com') ||
      url.contains('itunes.apple.com');

  factory ReleaseArtifact.fromJson(String platform, Map<String, dynamic> json) {
    return ReleaseArtifact(
      platform: platform,
      url: json['url'] as String? ?? '',
      sha256: (json['sha256'] as String? ?? '').trim().toLowerCase(),
      size: json['size'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'url': url,
        'sha256': sha256,
        'size': size,
      };
}

class AppRelease {
  final String channel;
  final String version; // 语义化版本，如 3.1.0
  final int buildNumber;
  final String releaseNotes;
  final int publishedAt; // 毫秒时间戳，0 表示未知
  final bool mandatory; // 强制更新
  final String minSupportedVersion; // 低于该版本必须升级，空串表示无限制
  final Map<String, ReleaseArtifact> artifacts;

  const AppRelease({
    required this.version,
    this.channel = 'stable',
    this.buildNumber = 0,
    this.releaseNotes = '',
    this.publishedAt = 0,
    this.mandatory = false,
    this.minSupportedVersion = '',
    this.artifacts = const {},
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final rawArtifacts = json['artifacts'];
    final map = <String, ReleaseArtifact>{};
    if (rawArtifacts is Map) {
      rawArtifacts.forEach((k, v) {
        if (v is Map) {
          map['$k'] = ReleaseArtifact.fromJson(
              '$k', Map<String, dynamic>.from(v));
        } else if (v is String) {
          // 简写形式："android": "https://..."
          map['$k'] = ReleaseArtifact(platform: '$k', url: v);
        }
      });
    }
    return AppRelease(
      channel: json['channel'] as String? ?? 'stable',
      version: (json['version'] as String? ?? '0.0.0').trim(),
      buildNumber: json['build_number'] as int? ?? 0,
      releaseNotes: json['release_notes'] as String? ??
          json['notes'] as String? ??
          '',
      publishedAt: json['published_at'] as int? ?? 0,
      mandatory: json['mandatory'] as bool? ?? false,
      minSupportedVersion:
          (json['min_supported_version'] as String? ?? '').trim(),
      artifacts: map,
    );
  }

  Map<String, dynamic> toJson() => {
        'channel': channel,
        'version': version,
        'build_number': buildNumber,
        'release_notes': releaseNotes,
        'published_at': publishedAt,
        'mandatory': mandatory,
        'min_supported_version': minSupportedVersion,
        'artifacts': artifacts.map((k, v) => MapEntry(k, v.toJson())),
      };

  /// 取当前平台的产物；找不到时回退到 `any`
  ReleaseArtifact? artifactFor(String platform) =>
      artifacts[platform] ?? artifacts['any'];

  DateTime? get publishedDateTime => publishedAt == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(publishedAt);

  String get displayVersion =>
      buildNumber > 0 ? '$version+$buildNumber' : version;
}

/// 版本比较结果
enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  ready, // 已下载并校验通过，等待用户安装
  failed,
}

/// 一次更新检查的结果
class UpdateCheckResult {
  final UpdateStatus status;
  final AppRelease? release;
  final String currentVersion;
  final String? error;

  /// 当前版本低于 `min_supported_version`
  final bool belowMinSupported;

  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.release,
    this.error,
    this.belowMinSupported = false,
  });

  bool get hasUpdate => status == UpdateStatus.available && release != null;

  /// 是否必须升级（清单标记强制，或当前版本已低于最低支持版本）
  bool get mustUpdate =>
      hasUpdate && ((release?.mandatory ?? false) || belowMinSupported);

  Map<String, dynamic> toJson() => {
        'status': status.toString().split('.').last,
        'current_version': currentVersion,
        'has_update': hasUpdate,
        'must_update': mustUpdate,
        'below_min_supported': belowMinSupported,
        'latest': release?.toJson(),
        'error': error,
      };
}
