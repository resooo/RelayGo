import 'package:flutter/material.dart';
import 'package:relaygo/config/theme.dart';
import 'package:relaygo/models/request_log.dart';
import 'package:relaygo/utils/formatters.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 请求日志详情页
///
/// 点击日志列表条目进入，完整展示单条请求的字段：
/// 请求行（方法 + 路径）、服务商 / Key / 模型、状态与耗时、
/// token 用量、字节数、流式 / 重试 / 缓存 / 限流标记、错误信息与时间。
class LogDetailScreen extends StatelessWidget {
  final RequestLog log;

  const LogDetailScreen({Key? key, required this.log}) : super(key: key);

  Color get _statusColor {
    if (log.isError) return AppTheme.danger;
    if (log.statusCode >= 400 && log.statusCode < 500) return AppTheme.warning;
    return AppTheme.success;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr('日志详情')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${log.statusCode}',
                  style: TextStyle(
                    fontFamily: AppTheme.monoFontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _statusColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _section(L10n.tr('请求'), [
            _kv('Method', log.method),
            _kv('Path', log.path, mono: true, wrap: true),
          ]),
          _section(L10n.tr('路由'), [
            _kv('服务商', log.provider),
            _kv('Key 名称', log.keyName),
            _kv('Key', log.keyMasked, mono: true),
            _kv('模型', log.model, mono: true, wrap: true),
            if (log.actualModel.isNotEmpty &&
                log.actualModel != log.model)
              _kv('实际模型', log.actualModel, mono: true, wrap: true),
            if (log.ruleName != null && log.ruleName!.isNotEmpty)
              _kv('路由规则', log.ruleName!),
          ]),
          _section(L10n.tr('结果'), [
            _kv('状态码', '${log.statusCode}', mono: true),
            _kv('耗时', Formatters.formatDuration(log.durationMs)),
            if (log.totalTokens > 0) ...[
              _kv('Prompt tokens', Formatters.formatNumber(log.promptTokens),
                  mono: true),
              _kv('Completion tokens',
                  Formatters.formatNumber(log.completionTokens),
                  mono: true),
              _kv('总 tokens', Formatters.formatNumber(log.totalTokens),
                  mono: true),
            ],
            _kv('请求字节', Formatters.formatNumber(log.requestBytes),
                mono: true),
            _kv('响应字节', Formatters.formatNumber(log.responseBytes),
                mono: true),
          ]),
          _section(L10n.tr('标记'), [
            _kv('流式', log.streaming ? '是' : '否'),
            _kv('重试次数', '${log.retries}'),
            _kv('命中缓存', log.cached ? '是' : '否'),
            _kv('限流维度',
                log.rateLimited.isEmpty ? '无' : log.rateLimited),
          ]),
          if (log.error != null && log.error!.isNotEmpty)
            _section(L10n.tr('错误'), [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.dangerSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  log.error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.danger,
                    fontFamily: AppTheme.monoFontFamily,
                    height: 1.5,
                  ),
                ),
              ),
            ]),
          _section(L10n.tr('时间'), [
            _kv('时间戳', Formatters.formatDateTime(log.timestamp), mono: true),
            _kv('日志 ID', log.id, mono: true, wrap: true),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.text2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {bool mono = false, bool wrap = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.text3),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.text,
                fontFamily: mono ? AppTheme.monoFontFamily : null,
                fontWeight: mono ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
