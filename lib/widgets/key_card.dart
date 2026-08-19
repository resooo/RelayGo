import 'package:flutter/material.dart';
import 'package:relaygo/config/theme.dart';
import 'package:relaygo/models/api_key.dart';
import 'package:relaygo/models/key_test.dart';
import 'package:relaygo/models/provider_config.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// Key 状态对应的颜色（对应设计稿 m3-dot：绿=有效 / 灰=禁用 / 橙=用尽 / 红=错误）
Color statusColor(KeyStatus status) {
  switch (status) {
    case KeyStatus.active:
      return AppTheme.brandGreen;
    case KeyStatus.inactive:
      return AppTheme.text3;
    case KeyStatus.exhausted:
      return AppTheme.warning;
    case KeyStatus.error:
      return AppTheme.danger;
  }
}

/// Key 状态徽章文案（对应设计稿 status-chip：有效 / 无效 / 测试中）
String statusLabel(KeyStatus status) {
  switch (status) {
    case KeyStatus.active:
      return L10n.tr('有效');
    case KeyStatus.inactive:
      return L10n.tr('禁用');
    case KeyStatus.exhausted:
      return L10n.tr('用尽');
    case KeyStatus.error:
      return L10n.tr('无效');
  }
}

/// 单个 API Key 行（对应设计稿 m3-row）
///
/// 状态圆点 + 掩码 Key（mono）+ 备注 + 状态徽章；点击切换启用状态，
/// 尾部更多菜单提供测试 / 编辑 / 删除。
class KeyCard extends StatelessWidget {
  final ApiKey apiKey;
  final VoidCallback? onTest;
  final VoidCallback? onDelete;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;
  final bool testing;

  const KeyCard({
    Key? key,
    required this.apiKey,
    this.onTest,
    this.onDelete,
    this.onToggle,
    this.onEdit,
    this.testing = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final k = apiKey;
    final testStatus = k.lastTestStatus;
    final sc = statusColor(k.status);
    final dotColor = testStatus != null
        ? Color(testStatus.colorValue)
        : sc;

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            // 状态圆点（m3-dot）
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withOpacity(0.35),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 中部：Key 名称 + 掩码 Key + 备注
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    k.name.isEmpty ? k.maskedKey : k.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(k),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.text2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 状态徽章（status-chip）
            _statusChip(k, testStatus),
            const SizedBox(width: 4),
            // 更多操作
            PopupMenuButton<String>(
              tooltip: L10n.tr('更多操作'),
              icon: const Icon(Icons.more_vert, size: 20, color: AppTheme.text3),
              onSelected: (v) {
                if (v == 'test') onTest?.call();
                if (v == 'edit') onEdit?.call();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (ctx) => [
                if (testing)
                  PopupMenuItem(
                      value: 'test',
                      enabled: false,
                      child: Text(L10n.tr('测试中...')))
                else
                  PopupMenuItem(
                      value: 'test', child: Text(L10n.tr('测试连接'))),
                if (onEdit != null)
                  PopupMenuItem(value: 'edit', child: Text(L10n.tr('编辑'))),
                if (onDelete != null)
                  PopupMenuItem(value: 'delete', child: Text(L10n.tr('删除'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 备注行：掩码 Key · 备注（对应设计稿 t2）
  String _subtitle(ApiKey k) {
    final parts = <String>[
      k.maskedKey,
      if (k.note.isNotEmpty) k.note,
    ];
    return parts.join(' · ');
  }

  /// 状态徽章（对应设计稿 status-chip ok/bad/warn）
  Widget _statusChip(ApiKey k, KeyTestStatus? testStatus) {
    // 优先展示最近测试结果；无测试记录时展示路由状态
    final style = _chipStyle(k, testStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: style.fg,
        ),
      ),
    );
  }

  _ChipStyle _chipStyle(ApiKey k, KeyTestStatus? testStatus) {
    if (testStatus != null) {
      switch (testStatus) {
        case KeyTestStatus.valid:
          return _ChipStyle(
              L10n.tr('有效'), const Color(0xFFA6F5C4), const Color(0xFF00210F));
        case KeyTestStatus.invalid:
        case KeyTestStatus.error:
          return _ChipStyle(
              L10n.tr('无效'), const Color(0xFFFFDAD6), const Color(0xFF410002));
        case KeyTestStatus.timeout:
          return _ChipStyle(
              L10n.tr('超时'), const Color(0x29FF9800), const Color(0xFFB26A00));
      }
    }
    switch (k.status) {
      case KeyStatus.active:
        return _ChipStyle(
            L10n.tr('有效'), const Color(0xFFA6F5C4), const Color(0xFF00210F));
      case KeyStatus.inactive:
        return _ChipStyle(L10n.tr('禁用'), const Color(0xFFF0F2F5), AppTheme.text2);
      case KeyStatus.exhausted:
        return _ChipStyle(
            L10n.tr('用尽'), const Color(0x29FF9800), const Color(0xFFB26A00));
      case KeyStatus.error:
        return _ChipStyle(
            L10n.tr('无效'), const Color(0xFFFFDAD6), const Color(0xFF410002));
    }
  }
}

/// 状态徽章配色（label / 背景 / 前景）
class _ChipStyle {
  final String label;
  final Color bg;
  final Color fg;

  const _ChipStyle(this.label, this.bg, this.fg);
}
