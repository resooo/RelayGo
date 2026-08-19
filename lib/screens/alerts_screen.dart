import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/l10n/app_strings.dart';
import 'package:relaygo/models/alert.dart';
import 'package:relaygo/utils/formatters.dart';

/// 告警中心（需求 2.2.2）
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({Key? key}) : super(key: key);

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  @override
  void initState() {
    super.initState();
    // 进入告警中心即视为全部已读，退出后首页红点消失
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = Provider.of<AppState>(context, listen: false);
      app.markAllAlertsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);
    final alerts = app.getAlerts();

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr('告警中心')),
        actions: [
          if (alerts.any((a) => !a.read))
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: L10n.tr('全部已读'),
              onPressed: () async {
                for (final a in alerts.where((a) => !a.read)) {
                  await app.markAlertRead(a.id);
                }
              },
            ),
          if (alerts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: L10n.tr('清空'),
              onPressed: () async {
                await app.clearAlerts();
              },
            ),
        ],
      ),
      body: alerts.isEmpty
          ? Center(
              child: Text(L10n.tr('暂无告警'), style: const TextStyle(color: Colors.grey)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final a = alerts[i];
                return Dismissible(
                  key: Key(a.id),
                  background: const ColoredBox(
                    color: Colors.red,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: Icon(Icons.delete, color: Colors.white),
                      ),
                    ),
                  ),
                  onDismissed: (_) => app.markAlertRead(a.id),
                  child: ListTile(
                    leading: _levelIcon(a.level),
                    title: Text(a.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.message),
                        Text(
                          '${a.event} · ${Formatters.formatRelative(a.timestamp)}',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: a.read
                        ? null
                        : const Icon(Icons.circle, size: 10, color: Colors.blue),
                    onTap: () {
                      if (!a.read) app.markAlertRead(a.id);
                    },
                  ),
                );
              },
            ),
    );
  }

  Widget _levelIcon(AlertLevel level) {
    final color = level == AlertLevel.critical
        ? Colors.red
        : level == AlertLevel.warning
            ? Colors.orange
            : Colors.blue;
    final icon = level == AlertLevel.critical
        ? Icons.error
        : level == AlertLevel.warning
            ? Icons.warning
            : Icons.info;
    return Icon(icon, color: color);
  }
}
