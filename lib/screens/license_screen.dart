import 'package:flutter/material.dart';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/config/theme.dart';
import 'package:relaygo/l10n/app_strings.dart';
import 'package:url_launcher/url_launcher.dart';

/// 开源协议页面
///
/// 说明：
///  - 项目本身基于 AGPL-3.0 协议开源；
///  - 列出项目使用到的核心开源依赖及其许可证；
///  - 列出项目实现时参考的开源项目，以表致谢；
///  - 「查看第三方组件完整许可证」通过 Flutter 内置的
///    [showLicensePage] 聚合展示所有 plugin 的 LICENSE。
class LicenseScreen extends StatelessWidget {
  const LicenseScreen({Key? key}) : super(key: key);

  /// 项目运行时使用的核心 Dart/Flutter 开源依赖
  static const List<_Dependency> _deps = [
    _Dependency('Flutter', 'Google', 'BSD-3-Clause',
        '跨平台 UI 框架', 'https://flutter.dev'),
    _Dependency('Dart SDK', 'Google', 'BSD-3-Clause',
        '编程语言', 'https://dart.dev'),
    _Dependency('hive', 'Simon Binder', 'Apache-2.0',
        '本地键值存储（Key、模型、日志、规则等）', 'https://pub.dev/packages/hive'),
    _Dependency('hive_flutter', 'Simon Binder', 'Apache-2.0',
        'Hive 的 Flutter 封装', 'https://pub.dev/packages/hive_flutter'),
    _Dependency('encrypt', 'Zac', 'BSD-3-Clause',
        'API Key 的 AES-256 加密', 'https://pub.dev/packages/encrypt'),
    _Dependency('provider', 'Remi Rousselet', 'MIT',
        '状态管理', 'https://pub.dev/packages/provider'),
    _Dependency('http', 'Dart Team', 'BSD-3-Clause',
        '网络请求与流式转发', 'https://pub.dev/packages/http'),
    _Dependency('crypto', 'Dart Team', 'BSD-3-Clause',
        'SHA-256：缓存键哈希、更新包校验', 'https://pub.dev/packages/crypto'),
    _Dependency('intl', 'Dart Team', 'BSD-3-Clause',
        '日期/数字格式化', 'https://pub.dev/packages/intl'),
    _Dependency('file_selector', 'Flutter Team', 'BSD-3-Clause',
        '跨平台文件选择器（Key 批量导入）', 'https://pub.dev/packages/file_selector'),
    _Dependency('url_launcher', 'Flutter Team', 'BSD-3-Clause',
        '打开外部链接', 'https://pub.dev/packages/url_launcher'),
    _Dependency('pointycastle', 'appsup-dart', 'MIT',
        '加密原语（encrypt 的底层实现）', 'https://pub.dev/packages/pointycastle'),
    _Dependency('asn1lib', 'Dirk Holtwick', 'BSD-2-Clause',
        'ASN.1 解析（加密依赖）', 'https://pub.dev/packages/asn1lib'),
    _Dependency('cupertino_icons', 'Flutter Team', 'MIT',
        'iOS 风格图标', 'https://pub.dev/packages/cupertino_icons'),
    _Dependency('flutter_lints', 'Dart Team', 'BSD-3-Clause',
        '代码规范检查（开发依赖）', 'https://pub.dev/packages/flutter_lints'),
  ];

  /// 项目实现时参考的开源项目
  static const List<_Dependency> _refs = [
    _Dependency('one-api', 'songquanpeng', 'MIT',
        '功能全面的 API 管理平台', 'https://github.com/songquanpeng/one-api'),
    _Dependency('new-api', 'Calcium-Ion', 'MIT',
        'one-api 的增强版本', 'https://github.com/QuantumNous/new-api'),
    _Dependency('openai-forward', 'beidongjiedeguang', 'MIT',
        '专注 OpenAI 的转发服务', 'https://github.com/beidongjiedeguang/openai-forward'),
    _Dependency('LiteLLM', 'BerriAI', 'MIT',
        '统一的多模型 API 网关', 'https://github.com/BerriAI/litellm'),
    _Dependency('ChatGPT-Next-Web', 'Yidadaa', 'MIT',
        '优秀的 UI 参考', 'https://github.com/ChatGPTNextWeb/NextChat'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = L10n.instance;
    return Scaffold(
      appBar: AppBar(title: Text(t.t('开源协议'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            context,
            title: t.t('项目许可证'),
            children: [
              _kv(context, t.t('项目'), Constants.appName),
              _kv(context, t.t('许可证'), 'GNU AGPL v3.0'),
              _kv(context, t.t('版本'), 'v${Constants.appVersion}'),
              const SizedBox(height: 8),
              Text(
                t.t('RelayGo 基于 AGPL-3.0 协议开源。\n\n'
                    '你可以自由使用、修改与再分发（需遵循 AGPL-3.0 条款：'
                    '基于本项目的衍生作品如向公众提供服务，需以相同协议开源完整源代码）。\n\n'
                    '本项目仅供学习与个人使用，请遵守各 AI 服务商的使用条款。'),
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 8),
              Row(
                  children: [
                  TextButton.icon(
                    icon: const Icon(Icons.description_outlined,
                        size: 18, color: AppTheme.accent),
                    label: const Text('LICENSE (GNU AGPL v3.0)'),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const _AbstractLicenseView(),
                    )),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            title: t.t('使用的开源项目'),
            subtitle: t.t('以下为项目运行时使用的核心开源依赖'),
            children: [
              for (final d in _deps) _depTile(context, d),
              TextButton.icon(
                icon: const Icon(Icons.shield_outlined,
                    size: 18, color: AppTheme.accent),
                label: Text(t.t('查看第三方组件完整许可证')),
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: Constants.appName,
                  applicationVersion: '${Constants.appVersion}+${Constants.appBuildNumber}',
                  applicationIcon: const Icon(Icons.swap_horiz,
                      size: 32, color: AppTheme.brandGreen),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            title: t.t('参考的项目'),
            subtitle: t.t('项目实现时参考并致谢以下开源项目'),
            children: [
              for (final r in _refs)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.star_outline,
                      size: 20, color: AppTheme.brandTeal),
                  title: Text(r.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(r.purpose),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(r.author,
                          style: const TextStyle(fontSize: 11, color: AppTheme.text3)),
                      Text(r.license,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.accent,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  onTap: () => _openUrl(r.url),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'AGPL-3.0 · ${t.t('仅供学习与个人使用')}',
              style: const TextStyle(fontSize: 12, color: AppTheme.text3),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context,
      {required String title, String? subtitle, required List<Widget> children}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: AppTheme.text3)),
            ],
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$k：',
              style: const TextStyle(fontSize: 13, color: AppTheme.text2)),
          const SizedBox(width: 6),
          Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _depTile(BuildContext context, _Dependency d) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading:
          const Icon(Icons.inventory_2_outlined, size: 20, color: AppTheme.brandGreen),
      title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(d.purpose),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(d.author,
              style: const TextStyle(fontSize: 11, color: AppTheme.text3)),
          Text(d.license,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold)),
        ],
      ),
      onTap: () => _openUrl(d.url),
    );
  }
}

void _openUrl(String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// 内嵌的 AGPL-3.0 摘要视图（完整文本较长，此处展示摘要并给出官方地址）
class _AbstractLicenseView extends StatelessWidget {
  const _AbstractLicenseView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = L10n.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('GNU AGPL v3.0')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.t('RelayGo 采用 GNU Affero General Public License v3.0 (AGPL-3.0)。\n\n'
                '核心要点：\n'
                '· 你可以自由使用、复制、修改与再分发；\n'
                '· 基于本项目的衍生作品，若通过**网络向第三方提供服务**，'
                '必须完整开源其源代码（与 Web/服务端场景对应）；\n'
                '· 修改后的版本必须使用相同协议授权，并保留版权声明；\n'
                '· 不附带任何担保。'),
                style: const TextStyle(fontSize: 13, height: 1.6)),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            const Text('完整许可证文本：',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('https://www.gnu.org/licenses/agpl-3.0.html',
                style: TextStyle(fontSize: 12, color: AppTheme.info)),
          ],
        ),
      ),
    );
  }
}

class _Dependency {
  final String name;
  final String author;
  final String license;
  final String purpose;
  final String url;
  const _Dependency(this.name, this.author, this.license, this.purpose, this.url);
}