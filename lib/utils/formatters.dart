import 'package:intl/intl.dart';

/// 格式化工具
class Formatters {
  /// API Key 脱敏：sk-abc...1234
  static String maskKey(String plainKey) {
    if (plainKey.isEmpty) return '****';
    if (plainKey.length <= 8) return '*' * plainKey.length;
    return '${plainKey.substring(0, 4)}••••${plainKey.substring(plainKey.length - 4)}';
  }

  /// 毫秒时间戳 -> yyyy-MM-dd HH:mm:ss
  static String formatDateTime(int millis) {
    if (millis == 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  /// 毫秒时间戳 -> yyyy-MM-dd（日志日期分隔）
  static String formatDate(int millis) {
    if (millis == 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  /// 相对时间（中文）
  static String formatRelative(int millis) {
    if (millis == 0) return '从未';
    final diff = DateTime.now().millisecondsSinceEpoch - millis;
    if (diff < 60000) return '刚刚';
    if (diff < 3600000) return '${(diff / 60000).floor()} 分钟前';
    if (diff < 86400000) return '${(diff / 3600000).floor()} 小时前';
    return '${(diff / 86400000).floor()} 天前';
  }

  /// 耗时（毫秒 -> 人类可读）
  static String formatDuration(int ms) {
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(2)}s';
  }

  /// 大数字千分位
  static String formatNumber(int n) {
    return NumberFormat.decimalPattern().format(n);
  }
}
