import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 导出 Key 对话框
///
/// 在移动端无法直接弹出系统保存对话框，改为展示 JSON 内容：
///  - 一键复制全部内容
///  - 用户自行粘贴到备忘录 / 文件保存
///  - 附带简要使用说明（重装后如何导入恢复）
class KeyExportDialog extends StatefulWidget {
  final String jsonContent;
  final int keyCount;

  const KeyExportDialog({
    Key? key,
    required this.jsonContent,
    required this.keyCount,
  }) : super(key: key);

  @override
  State<KeyExportDialog> createState() => _KeyExportDialogState();
}

class _KeyExportDialogState extends State<KeyExportDialog> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.jsonContent));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(L10n.tr('已复制到剪贴板')),
          duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.file_download_outlined, color: Colors.indigo),
          const SizedBox(width: 8),
          Text(L10n.tr('导出全部 Key')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 使用说明
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                L10n.fmt(
                    '共 {n} 个 Key，已生成 JSON 备份内容。\n'
                    '使用方法：\n'
                    '1. 点击「一键复制」复制全部内容；\n'
                    '2. 粘贴到备忘录 / 文件管理器保存为 .json 文件；\n'
                    '3. 重装应用后，在 Key 管理 → 批量导入中粘贴或选择该文件即可恢复。',
                    {'n': '${widget.keyCount}'}),
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 10),
            // JSON 内容
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    widget.jsonContent,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.tr('关闭')),
        ),
        ElevatedButton.icon(
          onPressed: _copy,
          icon: Icon(_copied ? Icons.check : Icons.copy),
          label: Text(_copied ? L10n.tr('已复制') : L10n.tr('一键复制')),
        ),
      ],
    );
  }
}
