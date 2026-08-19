import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/l10n/app_strings.dart';
import 'package:relaygo/models/routing_rule.dart';

/// 路由规则管理页（需求 2.2.3）
class RulesScreen extends StatelessWidget {
  const RulesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);
    final rules = app.rules;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr('路由规则')),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: L10n.tr('语法帮助'),
            onPressed: () => _showHelp(context),
          ),
        ],
      ),
      body: rules.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  L10n.tr('还没有规则。\n规则可在「请求路径 / 模型名 / 大小 / 时段 / IP / Token 数」等维度'
                      '智能路由请求到指定提供商或 key 分组。'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ReorderableListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              onReorder: (oldIndex, newIndex) => _reorder(app, rules, oldIndex, newIndex),
              children: [
                for (final rule in rules)
                  _RuleTile(
                    key: ValueKey(rule.id),
                    rule: rule,
                    onEdit: () => _showEditDialog(context, app, rule),
                    onDelete: () => _confirmDelete(context, app, rule),
                    onToggle: (v) => app.updateRule(rule.copyWith(enabled: v)),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showEditDialog(context, app, null),
      ),
    );
  }

  void _reorder(AppState app, List<RoutingRule> rules, int oldIndex, int newIndex) {
    final list = [...rules];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    // 按新顺序重排 order
    for (var i = 0; i < list.length; i++) {
      if (list[i].order != i) {
        app.updateRule(list[i].copyWith(order: i));
      }
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, AppState app, RoutingRule rule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.tr('删除规则')),
        content: Text(L10n.fmt('确认删除「{name}」？', {'name': rule.name})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(L10n.tr('取消'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(L10n.tr('删除'))),
        ],
      ),
    );
    if (confirm == true) await app.deleteRule(rule.id);
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.tr('规则语法')),
        content: SingleChildScrollView(
          child: Text(
            '${L10n.tr('条件（condition）：')}\n'
            '  request.model contains \'gpt-4\'\n'
            '  request.model in [\'gpt-4\', \'gpt-4o\']\n'
            '  request.size > 8192 && request.tokens < 4000\n'
            '  request.hour in [\'00:00-06:00\']   # 仅凌晨\n'
            '  request.ip matches \'^10\\.\'\n'
            '  request.provider == \'openai\' || request.tokens >= 8000\n'
            '  (支持 && || ! () contains starts_with ends_with matches in)\n\n'
            '${L10n.tr('动作（action）：')}\n'
            '  use_provider(\'openai\')\n'
            '  use_provider(\'anthropic\', strategy=\'priority\', group=\'free\')\n'
            '  block(\'该时段禁用\')\n\n'
            '${L10n.tr('order 越小越先匹配；命中第一条即生效。')}',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(L10n.tr('知道了'))),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, AppState app, RoutingRule? existing) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final condCtrl =
        TextEditingController(text: existing?.condition ?? 'request.model contains \'gpt-4\'');
    final actionCtrl = TextEditingController(
        text: existing?.action ?? "use_provider('openai')");
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final orderCtrl =
        TextEditingController(text: '${existing?.order ?? app.rules.length * 10}');
    var enabled = existing?.enabled ?? true;
    String? condError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(isEdit ? L10n.tr('编辑规则') : L10n.tr('新增规则')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: L10n.tr('名称')),
                ),
                TextField(
                  controller: condCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr('条件 (condition)'),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 2,
                  onChanged: (v) {
                    final err = app.ruleEngine.validateCondition(v);
                    setSt(() => condError = err);
                  },
                ),
                if (condError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(condError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                TextField(
                  controller: actionCtrl,
                  decoration: InputDecoration(
                    labelText: L10n.tr('动作 (action)'),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 2,
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: orderCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: L10n.tr('优先级(order)')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Switch(
                      value: enabled,
                      onChanged: (v) => setSt(() => enabled = v),
                    ),
                  ],
                ),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(labelText: L10n.tr('备注 (可选)')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(L10n.tr('取消'))),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final cond = condCtrl.text.trim();
                final action = actionCtrl.text.trim();
                if (name.isEmpty || cond.isEmpty || action.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(L10n.tr('名称 / 条件 / 动作 均不能为空'))),
                  );
                  return;
                }
                final err = app.ruleEngine.validateCondition(cond);
                if (err != null) {
                  setSt(() => condError = err);
                  return;
                }
                final order = int.tryParse(orderCtrl.text) ?? 100;
                final rule = RoutingRule(
                  id: existing?.id ?? _genId(),
                  name: name,
                  condition: cond,
                  action: action,
                  enabled: enabled,
                  order: order,
                  description: descCtrl.text.trim(),
                );
                if (isEdit) {
                  app.updateRule(rule);
                } else {
                  app.addRule(rule);
                }
                Navigator.pop(ctx);
              },
              child: Text(isEdit ? L10n.tr('保存') : L10n.tr('添加')),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  final RoutingRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  const _RuleTile({
    Key? key,
    required this.rule,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rule.enabled
                ? Colors.indigo.withOpacity(0.12)
                : Colors.grey.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('${rule.order}',
              style: TextStyle(
                  color: rule.enabled ? Colors.indigo : Colors.grey,
                  fontWeight: FontWeight.bold)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(rule.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Switch(
              value: rule.enabled,
              onChanged: onToggle,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IF  ${rule.condition}',
                style: const TextStyle(fontSize: 12, color: Colors.indigo)),
            Text('THEN  ${rule.action}',
                style: const TextStyle(fontSize: 12, color: Colors.teal)),
            if (rule.description.isNotEmpty)
              Text(rule.description,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onEdit),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

String _genId() {
  final t = DateTime.now().microsecondsSinceEpoch;
  return 'rule_$t';
}
