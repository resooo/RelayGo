/// 告警级别
enum AlertLevel { info, warning, critical }

extension AlertLevelX on AlertLevel {
  String get name => toString().split('.').last;

  static AlertLevel fromString(String v) {
    switch (v) {
      case 'critical':
        return AlertLevel.critical;
      case 'warning':
        return AlertLevel.warning;
      default:
        return AlertLevel.info;
    }
  }

  String get label {
    switch (this) {
      case AlertLevel.info:
        return '提示';
      case AlertLevel.warning:
        return '警告';
      case AlertLevel.critical:
        return '严重';
    }
  }
}

/// 告警事件类型（同时作为 Webhook 的 event 名）
class AlertEvent {
  static const String quotaWarning = 'quota.warning';
  static const String quotaExhausted = 'quota.exhausted';
  static const String keyStatusChanged = 'key.status_changed';
  static const String serverStarted = 'server.started';
  static const String serverStopped = 'server.stopped';
  static const String serverError = 'server.error';
  static const String errorRateHigh = 'error_rate.high';
  static const String dailyReport = 'report.daily';

  // —— Phase 3 ——
  static const String updateAvailable = 'app.update_available';
  static const String rateLimited = 'rate_limit.triggered';

  static const List<String> all = [
    quotaWarning,
    quotaExhausted,
    keyStatusChanged,
    serverStarted,
    serverStopped,
    errorRateHigh,
    dailyReport,
    updateAvailable,
    rateLimited,
  ];

  /// 事件的中文可读名（供订阅设置界面展示）
  static const Map<String, String> labels = {
    quotaWarning: '额度预警',
    quotaExhausted: '额度耗尽',
    keyStatusChanged: 'Key 状态变更',
    serverStarted: '服务启动',
    serverStopped: '服务停止',
    errorRateHigh: '错误率过高',
    dailyReport: '每日报告',
    updateAvailable: '发现新版本',
    rateLimited: '触发限流',
  };
}

/// 告警记录（需求 2.2.2 告警机制）
class Alert {
  final String id;
  final int timestamp;
  final String event; // AlertEvent 常量
  final AlertLevel level;
  final String title;
  final String message;
  final String? keyId;
  final Map<String, dynamic> data;
  final bool read;

  Alert({
    required this.id,
    required this.timestamp,
    required this.event,
    required this.level,
    required this.title,
    required this.message,
    this.keyId,
    this.data = const {},
    this.read = false,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as String,
      timestamp: json['timestamp'] as int? ?? 0,
      event: json['event'] as String? ?? '',
      level: AlertLevelX.fromString(json['level'] as String? ?? 'info'),
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      keyId: json['key_id'] as String?,
      data: json['data'] == null
          ? const {}
          : Map<String, dynamic>.from(json['data'] as Map),
      read: json['read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp,
      'event': event,
      'level': level.name,
      'title': title,
      'message': message,
      'key_id': keyId,
      'data': data,
      'read': read,
    };
  }

  Alert markRead() => Alert(
        id: id,
        timestamp: timestamp,
        event: event,
        level: level,
        title: title,
        message: message,
        keyId: keyId,
        data: data,
        read: true,
      );
}
