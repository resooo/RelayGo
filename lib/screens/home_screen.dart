import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/config/theme.dart';
import 'package:relaygo/screens/key_management_screen.dart';
import 'package:relaygo/screens/log_viewer_screen.dart';
import 'package:relaygo/screens/settings_screen.dart';
import 'package:relaygo/screens/rules_screen.dart';
import 'package:relaygo/screens/alerts_screen.dart';
import 'package:relaygo/screens/report_screen.dart';
import 'package:relaygo/screens/model_management_screen.dart';
import 'package:relaygo/screens/provider_management_screen.dart';
import 'package:relaygo/screens/free_api_screen.dart';
import 'package:relaygo/utils/network.dart';
import 'package:relaygo/l10n/app_strings.dart';

/// 首页（对应设计稿 HomeScreen）
///
/// 底部导航切换四个主页面：首页 / Keys / 日志 / 统计。
/// 首页：状态卡（呼吸圆点 + 运行状态）+ 今日统计 + 快捷操作 + 更多功能。
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  Timer? _uptimeTicker;

  @override
  void initState() {
    super.initState();
    // 运行时长实时走动：每秒刷新一次（仅服务运行时）
    _uptimeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final app = Provider.of<AppState>(context, listen: false);
      if (app.serverRunning) setState(() {});
    });
  }

  @override
  void dispose() {
    _uptimeTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppState>(context);
    final running = app.serverRunning;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // 品牌 Logo（渐变圆角方块 + 闪电）
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(Constants.appName),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: L10n.tr('设置'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _buildHomeTab(context, app, running),
          const KeyManagementScreen(),
          const LogViewerScreen(),
          const ReportScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: L10n.tr('首页'),
          ),
          const NavigationDestination(
            icon: Icon(Icons.key_outlined),
            selectedIcon: Icon(Icons.key),
            label: 'Keys',
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: L10n.tr('日志'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insert_chart_outlined),
            selectedIcon: const Icon(Icons.insert_chart),
            label: L10n.tr('统计'),
          ),
        ],
      ),
    );
  }

  // ———————— 首页 Tab ————————
  Widget _buildHomeTab(BuildContext context, AppState app, bool running) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusCard(context, app, running),
        const SizedBox(height: 16),
        _todayStats(app),
        const SizedBox(height: 16),
        _quickActions(context),
        const SizedBox(height: 16),
        _moreFeatures(context),
      ],
    );
  }

  /// 状态卡（对应设计稿：呼吸圆点 + Relay 服务 + 运行状态徽章 + 监听地址 + 运行时长 + 启停按钮）
  Widget _statusCard(BuildContext context, AppState app, bool running) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _PulseDot(color: running ? AppTheme.brandGreen : AppTheme.danger),
              const SizedBox(width: 10),
              Text(L10n.tr('Relay 服务'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text)),
              const Spacer(),
              // 状态徽章
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: running
                      ? const Color(0xFFA6F5C4)
                      : const Color(0xFFFFDAD6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  running ? L10n.tr('运行中') : L10n.tr('已停止'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: running
                        ? const Color(0xFF00210F)
                        : const Color(0xFF410002),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 监听地址（本机 + 局域网，点击复制完整 URL）
          Row(
            children: [
              Text(L10n.tr('监听地址'),
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.text2)),
              const Spacer(),
              Icon(Icons.copy, size: 13, color: AppTheme.text3),
              const SizedBox(width: 4),
              Text(L10n.tr('点击复制'),
                  style: const TextStyle(fontSize: 11, color: AppTheme.text3)),
            ],
          ),
          const SizedBox(height: 6),
          _copyRow(context, L10n.tr('本机'),
              'http://127.0.0.1:${app.proxy.port}/v1'),
          const SizedBox(height: 4),
          FutureBuilder<String?>(
            future: NetworkUtil.localIpv4(),
            builder: (context, snap) {
              final lan = snap.data;
              final url = lan == null || lan.isEmpty
                  ? 'http://0.0.0.0:${app.proxy.port}/v1'
                  : 'http://$lan:${app.proxy.port}/v1';
              return _copyRow(context, L10n.tr('局域网'), url);
            },
          ),
          const SizedBox(height: 8),
          // 运行时长
          Row(
            children: [
              Text(L10n.tr('运行时长'),
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.text2)),
              const Spacer(),
              Text(
                running ? _uptimeText(app) : '—',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 启停按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: Icon(running ? Icons.stop : Icons.play_arrow),
              label: Text(running ? L10n.tr('停止服务') : L10n.tr('启动服务')),
              style: FilledButton.styleFrom(
                backgroundColor: running ? AppTheme.danger : AppTheme.brandGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                try {
                  await app.toggleServer();
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${L10n.tr('服务启动失败')}: $e'),
                    backgroundColor: AppTheme.danger,
                  ));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  String _uptimeText(AppState app) {
    final start = app.serverStartedAt;
    if (start == null) return '—';
    final d = DateTime.now().difference(start);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final hour = L10n.tr('小时');
    final min = L10n.tr('分');
    final sec = L10n.tr('秒');
    if (h > 0) return '$h $hour $m $min $s $sec';
    if (m > 0) return '$m $min $s $sec';
    return '$s $sec';
  }

  Widget _monoTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
            fontFamily: AppTheme.monoFontFamily,
            fontSize: 12,
            color: AppTheme.text2),
      ),
    );
  }

  /// 可点击复制的监听地址行（点击复制完整 URL 到剪贴板）
  Widget _copyRow(BuildContext context, String label, String url) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${L10n.tr('已复制到剪贴板')}: $url'),
          duration: const Duration(seconds: 2),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 12, color: AppTheme.text2)),
            const SizedBox(width: 8),
            Expanded(child: _monoTag(url)),
          ],
        ),
      ),
    );
  }

  /// 今日统计（对应设计稿：请求数 / 成功数 / 错误数 三列）
  Widget _todayStats(AppState app) {
    final s = app.logService.stats();
    final success = s.total - s.errors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.tr('今日统计'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.text)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statMini('${s.total}', L10n.tr('请求数'), AppTheme.text),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statMini('$success', L10n.tr('成功数'), AppTheme.brandGreen),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statMini('${s.errors}', L10n.tr('错误数'), AppTheme.danger),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statMini(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTheme.monoFontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.text2)),
        ],
      ),
    );
  }

  /// 快捷操作（对应设计稿：API Keys / 模型同步 / 请求日志 / 统计分析）
  Widget _quickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.tr('快捷操作'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.text)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _quickTile(
                context,
                icon: Icons.key,
                title: 'API Keys',
                subtitle: L10n.count(Provider.of<AppState>(context).totalKeyCount),
                alt: false,
                page: const KeyManagementScreen(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickTile(
                context,
                icon: Icons.sync,
                title: L10n.tr('模型同步'),
                subtitle: L10n.count(Provider.of<AppState>(context).models.length),
                alt: true,
                page: const ModelManagementScreen(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _quickTile(
                context,
                icon: Icons.receipt_long,
                title: L10n.tr('请求日志'),
                subtitle: L10n.tr('查看记录'),
                alt: false,
                page: const LogViewerScreen(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickTile(
                context,
                icon: Icons.insert_chart,
                title: L10n.tr('统计报表'),
                subtitle: L10n.tr('周期报表与导出'),
                alt: true,
                page: const ReportScreen(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool alt,
    required Widget page,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: alt
                    ? const Color(0xFFC7EEE1)
                    : const Color(0xFFA6F5C4),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Icon(
                icon,
                size: 20,
                color: alt
                    ? const Color(0xFF00201A)
                    : const Color(0xFF00210F),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.text)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.text2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 更多功能（其余功能入口）
  Widget _moreFeatures(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.tr('更多功能'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.text)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _featureTile(context, Icons.cloud_outlined, L10n.tr('提供商管理'),
                  L10n.tr('内置与自定义 AI 服务商'), const ProviderManagementScreen()),
              _divider(),
              _featureTile(context, Icons.rule, L10n.tr('路由规则'), L10n.tr('按条件智能路由'),
                  const RulesScreen()),
              _divider(),
              _featureTile(context, Icons.notifications_outlined, L10n.tr('告警中心'),
                  L10n.tr('配额与错误率告警'), const AlertsScreen()),
              _divider(),
              _featureTile(context, Icons.assessment_outlined, L10n.tr('统计报表'),
                  L10n.tr('周期报表与导出'), const ReportScreen()),
              _divider(),
              _featureTile(context, Icons.celebration_outlined, L10n.tr('免费 API'),
                  L10n.tr('免费大模型接口推荐'), const FreeApiScreen()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider() => const Divider(
      height: 1, thickness: 1, indent: 16, endIndent: 16, color: AppTheme.border);

  Widget _featureTile(BuildContext context, IconData icon, String title,
      String subtitle, Widget page) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Icon(icon, size: 18, color: AppTheme.brandGreen),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.text)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppTheme.text2)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.text3),
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
    );
  }
}

/// 呼吸圆点（对应设计稿 m3-dot green pulse）
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _anim = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Container(
              width: 18 + _anim.value * 12,
              height: 18 + _anim.value * 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity((1 - _anim.value) * 0.35),
              ),
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(color: widget.color.withOpacity(0.5), blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
