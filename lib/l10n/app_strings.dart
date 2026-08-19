/// 轻量多语言支持（需求 3：中英文）
///
/// 设计：以**中文**作为键，[L10n.t] 在 `zh` 时直接返回键本身，
/// 在 `en` 时查 [_en] 映射，未命中映射则回退中文。
/// 这样既有中文的项目无需维护两份中文文案，又能让新界面快速支持英文。
///
/// 用法：
/// ```dart
/// Text(L10n.tr('设置'));                 // 随 AppState 的 language 切换
/// Text(L10n.instance.t('检查更新'));      // 等价写法
/// ```
class L10n {
  L10n._();

  /// 全局单例（语言在 AppState 初始化 / 保存设置时同步）
  static final L10n instance = L10n._();

  /// 当前语言：'zh' / 'en'
  String language = 'zh';

  /// 英文映射表（键为中文）
  static const Map<String, String> _en = {
    // ===== 通用 =====
    '设置': 'Settings',
    '保存设置': 'Save',
    '服务器': 'Server',
    '日志管理': 'Log Management',
    '额度监控与告警': 'Quota & Alerts',
    '路由规则与限流': 'Rules & Rate Limit',
    '外观与语言': 'Appearance & Language',
    '安全': 'Security',
    '关于与更新': 'About & Update',
    '取消': 'Cancel',
    '保存': 'Save',
    '添加': 'Add',
    '删除': 'Delete',
    '完成': 'Done',
    '关闭': 'Close',
    '确定': 'OK',
    '复制': 'Copy',
    '刷新': 'Refresh',
    '重试': 'Retry',
    '导出': 'Export',
    '导入': 'Import',
    '同步': 'Sync',
    '检查': 'Check',
    '查看': 'View',
    '修改': 'Edit',
    '全部': 'All',
    '成功': 'Success',
    '错误': 'Error',
    '无效': 'invalid',
    '未知': 'Unknown',
    '已复制到剪贴板': 'Copied to clipboard',
    '已复制': 'Copied',
    '一键复制': 'Copy All',
    '知道了': 'Got it',
    '名称': 'Name',
    '优先级': 'Priority',
    '权重': 'Weight',
    '提供商': 'Provider',
    '服务商': 'Provider',
    '监听地址': 'Listen Address',
    '运行时长': 'Uptime',
    '语言': 'Language',
    '端口': 'Port',
    '测试': 'Test',
    '次': 'req',
    '到': 'to',
    '已导出': 'Exported',
    '条记录': 'records',
    '服务启动失败': 'Failed to start server',

    // ===== 首页 =====
    '首页': 'Home',
    '日志': 'Logs',
    '统计': 'Stats',
    '运行中': 'Running',
    '已停止': 'Stopped',
    '停止服务': 'Stop Server',
    '启动服务': 'Start Server',
    'Relay 服务': 'Relay Service',
    '点击复制': 'Tap to copy',
    '本机': 'Local',
    '局域网': 'LAN',
    '小时': 'h',
    '分': 'm',
    '秒': 's',
    '今日统计': "Today's Stats",
    '请求数': 'Requests',
    '成功数': 'Success',
    '错误数': 'Errors',
    '快捷操作': 'Quick Actions',
    '模型同步': 'Sync Models',
    '请求日志': 'Request Logs',
    '统计分析': 'Analytics',
    '查看记录': 'View logs',
    '图表数据': 'Charts & data',
    '更多功能': 'More',
    '提供商管理': 'Providers',
    '内置与自定义 AI 服务商': 'Built-in & custom AI providers',
    '路由规则': 'Routing Rules',
    '按条件智能路由': 'Route by conditions',
    '告警中心': 'Alerts',
    '配额与错误率告警': 'Quota & error-rate alerts',
    '统计报表': 'Reports',
    '周期报表与导出': 'Periodic reports & export',
    '免费 API': 'Free APIs',
    '免费大模型接口推荐': 'Free LLM API recommendations',

    // ===== 服务器 =====
    '监听端口': 'Listen Port',
    '负载均衡策略': 'Load Balance Strategy',
    '服务器配置': 'Server',
    'Relay 服务监听端口': 'Relay server listen port',
    '0.0.0.0（所有网卡）或 127.0.0.1（仅本机）':
        '0.0.0.0 (all interfaces) or 127.0.0.1 (local only)',
    '轮询': 'Round Robin',
    '加权轮询': 'Weighted Round Robin',
    '最少连接': 'Least Connections',
    '响应时间': 'Response Time',
    '智能': 'Smart',
    '自动启动': 'Auto Start',
    '开机后自动运行服务': 'Run server automatically after boot',
    '局域网访问': 'LAN Access',
    '允许局域网内设备连接': 'Allow LAN devices to connect',
    '端口不合法': 'Invalid port',
    '修改端口': 'Edit Port',
    '设置已保存': 'Settings saved',
    '若未弹出授权框，请到「系统设置 → 应用 → 电池优化」中手动允许':
        'If no dialog appears, enable it manually in System Settings → Apps → Battery Optimization',
    '已是最新版本 v1.0.1': 'Already the latest version v1.0.1',
    '开源协议': 'Open Source License',
    '项目许可证': 'Project License',
    '项目': 'Project',
    '许可证': 'License',
    '版本': 'Version',
    'RelayGo 基于 MIT License 开源。\n\n'
        '本项目仅供学习与个人使用，请遵守各 AI 服务商的使用条款。':
        'RelayGo is open source under the MIT License.\n\n'
            'For learning and personal use only. Please comply with each AI provider\'s terms of service.',
    '使用的开源项目': 'Open Source Projects Used',
    '以下为项目运行时使用的核心开源依赖':
        'Core open-source dependencies used at runtime',
    '查看第三方组件完整许可证': 'View Complete Third-Party Licenses',
    '参考的项目': 'Referenced Projects',
    '项目实现时参考并致谢以下开源项目':
        'We referenced and thank the following open-source projects',
    'RelayGo 基于 AGPL-3.0 协议开源。\n\n'
        '你可以自由使用、修改与再分发（需遵循 AGPL-3.0 条款：'
        '基于本项目的衍生作品如向公众提供服务，需以相同协议开源完整源代码）。\n\n'
        '本项目仅供学习与个人使用，请遵守各 AI 服务商的使用条款。':
        'RelayGo is open source under the AGPL-3.0 license.\n\n'
            'You may freely use, modify and redistribute it (subject to AGPL-3.0: '
            'if your derivative provides a service to the public, you must '
            'disclose the complete source under the same license).\n\n'
            'For learning and personal use only. Please comply with each AI provider\'s terms of service.',
    'RelayGo 采用 GNU Affero General Public License v3.0 (AGPL-3.0)。\n\n'
        '核心要点：\n'
        '· 你可以自由使用、复制、修改与再分发；\n'
        '· 基于本项目的衍生作品，若通过**网络向第三方提供服务**，'
        '必须完整开源其源代码（与 Web/服务端场景对应）；\n'
        '· 修改后的版本必须使用相同协议授权，并保留版权声明；\n'
        '· 不附带任何担保。':
        'RelayGo is distributed under the GNU Affero General Public License v3.0 (AGPL-3.0).\n\n'
            'Key points:\n'
            '· You may freely use, copy, modify and redistribute it;\n'
            '· If your derivative provides a service to the public **over a network**, '
            'you must disclose its complete source code (covers web/server scenarios);\n'
            '· Modified versions must be licensed under the same license and retain copyright notices;\n'
            '· Provided without warranty.',
    '仅供学习与个人使用': 'For learning & personal use only',

    // ===== Key 管理 =====
    'Key 管理': 'Key Management',
    '自动测试间隔': 'Auto Test Interval',
    '1 小时': '1 hour',
    '6 小时': '6 hours',
    '12 小时': '12 hours',
    '24 小时': '24 hours',
    '失效自动禁用': 'Auto-disable on failure',
    '测试失败自动停用 Key': 'Auto-disable keys that fail testing',
    '启用规则引擎': 'Enable Rule Engine',
    '按规则智能路由请求': 'Route requests by rules',
    '单请求最多切换 key 数': 'Max Key Switches / Request',
    '搜索 Key...': 'Search keys...',
    '筛选服务商': 'Filter by provider',
    '全部服务商': 'All providers',
    '还没有添加任何 Key\n点击右下角按钮新增': 'No keys yet\nTap the button below to add',
    '没有匹配的 Key': 'No matching keys',
    '测试全部': 'Test All',
    '连接完成': 'Test complete',
    '连接成功': 'Connected',
    '连接失败': 'Failed',
    '连接超时': 'Timeout',
    '连接异常': 'Error',
    '删除 Key': 'Delete Key',
    '确认删除「{name}」？此操作不可撤销。': 'Delete "{name}"? This cannot be undone.',
    '成功导入 {n} 个 Key': 'Imported {n} keys',
    '暂无 Key 可导出': 'No keys to export',
    'Key 已添加，请同步模型列表': 'Key added. Please sync the model list',
    '去同步': 'Sync Now',

    // ===== 添加/编辑 Key 对话框 =====
    '编辑 API Key': 'Edit API Key',
    '添加 API Key': 'Add API Key',
    '留空则自动生成': 'Auto-generated if empty',
    '留空则保持不变': 'Leave empty to keep unchanged',
    '支持一行一个 Key 批量添加': 'One key per line for batch add',
    '请填写至少一个 API Key': 'Enter at least one API Key',
    'API URL': 'API URL',
    '例如 https://api.openai.com/v1': 'e.g. https://api.openai.com/v1',
    '请填写 API URL': 'Please enter API URL',
    'URL 必须以 http:// 或 https:// 开头':
        'URL must start with http:// or https://',
    'API 路径': 'API Path',
    '默认 /chat/completions': 'Default /chat/completions',
    '备注说明(可选)': 'Note (optional)',
    '选填，例如：账号A-免费额度': 'Optional, e.g. Account A - free quota',
    '分组(可选)': 'Group (optional)',
    '用于规则按组路由': 'Used for group-based routing',
    '每分钟上限(RPM)': 'Rate Limit (RPM)',
    '每日额度(token)': 'Daily Quota (tokens)',
    '(自定义)': '(custom)',

    // ===== 日志 =====
    '状态筛选': 'Status',
    '暂无匹配日志': 'No matching logs',
    '日志详情': 'Log Detail',
    '请求': 'Request',
    '路由': 'Routing',
    '结果': 'Result',
    '标记': 'Flags',
    '时间': 'Time',
    'Key 名称': 'Key Name',
    '模型': 'Model',
    '实际模型': 'Actual Model',
    '状态码': 'Status Code',
    '耗时': 'Duration',
    '流式': 'Streaming',
    '重试次数': 'Retries',
    '命中缓存': 'Cached',
    '限流维度': 'Rate Limit',
    '时间戳': 'Timestamp',
    '日志 ID': 'Log ID',

    // ===== 统计报表 =====
    '导出 JSON': 'Export JSON',
    '导出 CSV': 'Export CSV',
    '导出 Markdown': 'Export Markdown',
    '日报': 'Daily',
    '周报': 'Weekly',
    '月报': 'Monthly',
    '错误率': 'Error Rate',
    'Token': 'Tokens',
    '平均耗时': 'Avg Latency',
    'P95': 'P95',
    '缓存命中': 'Cache Hits',
    '缓存命中率': 'Cache Hit Rate',
    '环比请求': 'Requests WoW',
    '每日请求趋势': 'Daily Request Trend',
    '每日错误趋势': 'Daily Error Trend',
    'Top 模型': 'Top Models',
    'Top Key': 'Top Keys',
    'Top 提供商': 'Top Providers',
    '（暂无数据）': '(no data)',
    '(未知)': '(unknown)',
    '限流触发': 'Rate Limit Triggers',
    '缓存统计': 'Cache Stats',
    '命中': 'Hits',
    '未命中': 'Misses',
    '命中率': 'Hit rate',
    '条目': 'Entries',

    // ===== 统计页（旧） =====
    '今日': 'Today',
    '本周': 'This Week',
    '本月': 'This Month',
    '请求总数': 'Total Requests',
    'Token 消耗': 'Token Usage',

    // ===== 模型管理 =====
    '模型管理': 'Models',
    '清理已下线模型': 'Clean Up Removed Models',
    '同步历史': 'Sync History',
    '同步所有模型': 'Sync All Models',
    '模型总数：{total}（已启用 {enabled}）': 'Total: {total} (enabled {enabled})',
    '最后同步：{time}': 'Last sync: {time}',
    '尚未同步，点击右上角同步模型': 'Not synced yet. Tap sync in the top right',
    '已下线 {count} 个，点击右上角清理': '{count} removed. Tap to clean up',
    '搜索模型名称 / 服务商': 'Search model name / provider',
    '还没有模型，点击右上角「同步」从各服务商拉取':
        'No models yet. Tap "Sync" in the top right to fetch from providers',
    '没有需要清理的已下线模型': 'No removed models to clean up',
    '将从模型库中删除以下已下线（deprecated）模型：\n\n{detail}\n\n删除后第三方将无法再获取这些模型。':
        'The following deprecated models will be removed from the library:\n\n{detail}\n\nAfter removal, third parties can no longer fetch these models.',
    '已清理 {n} 个已下线模型': 'Removed {n} deprecated models',
    '已下线': 'Removed',
    '暂无同步记录': 'No sync records',
    '共 {n} 个模型': '{n} models total',
    '失败：{err}': 'Failed: {err}',

    // ===== 提供商管理 =====
    '内置提供商无法删除，但可被同 ID 自定义覆盖':
        'Built-in providers cannot be deleted, but can be overridden by a custom provider with the same ID',
    '暂无提供商': 'No providers',
    '关于提供商': 'About Providers',
    '内置提供商预设了市面上主流的 AI 服务商信息，可以直接使用。\n\n'
        '如果内置提供商的 API URL 或路径需要修改，可以添加一个同名的自定义提供商来覆盖。\n\n'
        '自定义的提供商可以自由编辑和删除。':
        'Built-in providers preset popular AI provider info for direct use.\n\n'
            'If a built-in provider\'s API URL or path needs changes, add a custom provider with the same name to override it.\n\n'
            'Custom providers can be freely edited and deleted.',
    '删除提供商': 'Delete Provider',
    '确认删除「{name}」？\n已关联该提供商的 API Key 需要重新选择提供商。':
        'Delete "{name}"?\nAPI keys linked to this provider will need to reselect a provider.',
    '内置': 'Built-in',
    '自定义': 'Custom',
    '需手动填写 API URL': 'Enter API URL manually',
    'API 路径: {path}': 'API Path: {path}',
    '编辑提供商': 'Edit Provider',
    '添加提供商': 'Add Provider',
    '请填写名称': 'Please enter a name',
    '模型列表路径': 'Model List Path',
    '默认 /models': 'Default /models',

    // ===== 路由规则 =====
    '语法帮助': 'Syntax Help',
    '还没有规则。\n规则可在「请求路径 / 模型名 / 大小 / 时段 / IP / Token 数」等维度'
        '智能路由请求到指定提供商或 key 分组。':
        'No rules yet.\nRules can route requests by path / model / size / time / IP / token count to specific providers or key groups.',
    '删除规则': 'Delete Rule',
    '确认删除「{name}」？': 'Delete "{name}"?',
    '规则语法': 'Rule Syntax',
    '条件（condition）：': 'Conditions:',
    '动作（action）：': 'Actions:',
    'order 越小越先匹配；命中第一条即生效。':
        'Lower order matches first; the first match takes effect.',
    '编辑规则': 'Edit Rule',
    '新增规则': 'New Rule',
    '条件 (condition)': 'Condition',
    '动作 (action)': 'Action',
    '优先级(order)': 'Priority (order)',
    '备注 (可选)': 'Note (optional)',
    '名称 / 条件 / 动作 均不能为空': 'Name / condition / action cannot be empty',

    // ===== 告警中心 =====
    '全部已读': 'Mark all read',
    '清空': 'Clear',
    '暂无告警': 'No alerts',

    // ===== 批量测试 =====
    '测试全部 Key': 'Test All Keys',
    '正在测试 {done}/{total} ...': 'Testing {done}/{total} ...',
    '当前：{name}': 'Current: {name}',
    '准备中': 'preparing',
    '测试完成！': 'Test complete!',
    '有效：{n}': 'Valid: {n}',
    '无效：{n}': 'Invalid: {n}',
    '超时：{n}': 'Timeout: {n}',
    '异常：{n}': 'Error: {n}',
    '失败 Key 列表：': 'Failed Keys:',
    '原因：{reason}': 'Reason: {reason}',
    '导出结果': 'Export Result',
    '删除无效': 'Delete Invalid',
    '禁用无效': 'Disable Invalid',
    '删除无效 Key': 'Delete Invalid Keys',
    '确认删除 {n} 个无效/失败 Key？此操作不可撤销。':
        'Delete {n} invalid/failed keys? This cannot be undone.',
    '测试结果': 'Test Results',
    '已禁用 {n} 个无效 Key': 'Disabled {n} invalid keys',
    '已删除 {n} 个无效 Key': 'Deleted {n} invalid keys',

    // ===== 批量导入 =====
    '批量导入 Key': 'Import Keys',
    '从文件读取': 'Read from File',
    '支持 .txt / .json / .csv，或下方直接粘贴':
        'Supports .txt / .json / .csv, or paste below',
    '格式说明：': 'Format:',
    '在此粘贴 Key 列表，或点击「从文件读取」':
        'Paste keys here, or tap "Read from File"',
    '已识别 {n} 个 Key': 'Detected {n} keys',
    '读取文件失败：{err}': 'Failed to read file: {err}',
    '未解析到有效 Key': 'No valid keys parsed',
    '导入失败：{err}': 'Import failed: {err}',
    '文本 / JSON / CSV': 'Text / JSON / CSV',
    '所有文件': 'All files',

    // ===== 导出 Key =====
    '导出全部 Key': 'Export All Keys',
    '共 {n} 个 Key，已生成 JSON 备份内容。\n'
        '使用方法：\n'
        '1. 点击「一键复制」复制全部内容；\n'
        '2. 粘贴到备忘录 / 文件管理器保存为 .json 文件；\n'
        '3. 重装应用后，在 Key 管理 → 批量导入中粘贴或选择该文件即可恢复。':
        '{n} keys, JSON backup generated.\n'
            'How to use:\n'
            '1. Tap "Copy All" to copy everything;\n'
            '2. Paste into Notes / File Manager and save as .json;\n'
            '3. After reinstalling, paste or select this file in Key Management → Import.',

    // ===== 模型同步进度 =====
    '同步模型': 'Sync Models',
    '正在同步 {done}/{total} 个服务商': 'Syncing {done}/{total} providers',
    '同步完成': 'Sync complete',
    '正在同步 {p} 的模型列表...': 'Syncing models for {p}...',
    '{p} 同步完成，共 {n} 个模型': '{p} synced, {n} models',
    '{p} 同步失败：{err}': '{p} sync failed: {err}',
    '成功 {ok} 个服务商，失败 {fail} 个': '{ok} succeeded, {fail} failed',
    '新增 {n} · 更新 {u} · 下线 {r} · 共 {t} 个模型':
        'New {n} · Updated {u} · Removed {r} · {t} models',

    // ===== 免费 API =====
    '免费 API 推荐': 'Free API Recommendations',
    '暂无数据': 'No data',
    '加载失败：{err}': 'Load failed: {err}',
    '免责声明：免费政策可能随时变动，使用前请务必点击「官方文档」进行最终确认。':
        'Disclaimer: free policies may change anytime. Always confirm via the official docs before use.',
    '数据来源：{src}': 'Source: {src}',
    '数据版本：{v}': 'Version: {v}',
    '生成日期：{d}': 'Generated: {d}',
    '本地更新：{t}': 'Local update: {t}',
    '允许商用': 'Commercial OK',
    '禁止商用': 'No commercial',
    '免费类型：{v}': 'Type: {v}',
    '免费模式：{v}': 'Mode: {v}',
    '已验证：{v}': 'Verified: {v}',
    '最佳用途': 'Best For',
    '免费额度详情': 'Free Tier',
    '速率限制': 'Rate Limits',
    '限制条件': 'Restrictions',
    '需要手机验证：{v}': 'Phone required: {v}',
    '需要信用卡：{v}': 'Card required: {v}',
    '允许商用：{v}': 'Commercial: {v}',
    'OpenAI 接口兼容：{v}': 'OpenAI compatible: {v}',
    '支持模态': 'Modalities',
    '免费模型列表': 'Free Models',
    'OpenAI 兼容接口地址': 'OpenAI-compatible Base URL',
    '不适用': 'N/A',
    '环境变量密钥名': 'Env Variable Key',
    '未说明': 'Not specified',
    '额度过期时间': 'Quota Expiry',
    '最近验证日期': 'Last Verified',
    '重要注意事项': 'Important Notes',
    '查看官方文档': 'View Official Docs',
    '无法打开链接': 'Cannot open link',

    // ===== 更新 =====
    '在线更新 (3.0)': 'Online Update',
    '更新源地址': 'Update Feed URL',
    '更新渠道': 'Update Channel',
    '启动时自动检查更新': 'Auto-check on Startup',
    '检查更新': 'Check for Update',
    '当前版本': 'Current Version',
    '最新版本': 'Latest Version',
    '已是最新': 'Up to date',
    '发现新版本': 'Update Available',
    '下载更新': 'Download Update',
    '正在下载': 'Downloading',
    '发布说明': 'Release Notes',
    '强制更新': 'Mandatory',
    '立即更新': 'Update Now',
    '该平台需前往应用商店更新': 'Please update via the app store on this platform',
    '该版本没有提供当前平台的安装包': 'No package for the current platform',
    '正在检查': 'Checking',
    '检查更新失败': 'Update check failed',
    '（无）': '(none)',
    '下载失败': 'Download failed',
    '已下载，可安装': 'Downloaded, ready to install',
    '稳定版': 'Stable',
    '测试版': 'Beta',
    '运行平台': 'Platform',
    // —— GitHub Releases 更新源（方案一）——
    'GitHub 发布仓库': 'GitHub Release Repo',
    '未配置，走静态清单回退': 'Not set; falls back to static manifest',
    '格式：owner/repo': 'Format: owner/repo',
    '留空将回退到静态更新清单': 'Leave empty to use the static update manifest',

    // ===== 设置页补充 =====
    '中文': 'Chinese',
    '最新版': 'Latest',
    '（生物识别 / PIN）': '(Biometric / PIN)',
    '0 = 不自动清理': '0 = no auto cleanup',
    '0 = 不限制': '0 = unlimited',
    '达到 {pct}% 触发预警': 'Alert at {pct}%',
    '超过 {pct}% 触发': 'Trigger above {pct}%',
    '监听 {host}:{port}': 'Listening on {host}:{port}',
    '检测到服务异常退出，看门狗已自动重启':
        'Server exited abnormally; watchdog restarted it',
    '有可用更新': 'Update available',
    '缓存可复用幂等的 2xx 响应': 'Cache reusable idempotent 2xx responses',
    '应用启动时从各服务商拉取最新模型':
        'Fetch latest models from providers on startup',
    '同步后未出现的历史模型标记为已下线':
        'Mark models missing after sync as removed',
    '额度 / 错误率触发时通知': 'Notify on quota / error-rate triggers',
    '前台服务 + 常驻通知，防止系统回收进程':
        'Foreground service + persistent notification to prevent process kill',
    '加入白名单，避免 Doze 模式被杀':
        'Add to whitelist to avoid Doze mode kill',

    // ===== Key 卡片 / 测试 =====
    '更多操作': 'More actions',
    '测试中...': 'Testing...',
    '测试连接': 'Test connection',
    '有效': 'Valid',
    '禁用': 'Disabled',
    '用尽': 'Exhausted',
    '超时': 'Timeout',
    '连接成功：{name}': 'Connected: {name}',
    '连接失败：{name}（{err}）': 'Failed: {name} ({err})',
    '连接超时：{name}': 'Timeout: {name}',
    '连接异常：{name}（{err}）': 'Error: {name} ({err})',
    '测试 {name}': 'Test {name}',
    '有效：{n} 个': 'Valid: {n}',
    '无效：{n} 个': 'Invalid: {n}',
    '超时：{n} 个': 'Timeout: {n}',
    '异常：{n} 个': 'Error: {n}',
    '{name} (自定义)': '{name} (custom)',
    'API Key': 'API Key',

    // ===== 日志页补充 =====
    '{n} 条记录': '{n} records',
    '已导出 {n} 条到：{path}': 'Exported {n} records to: {path}',

    // ===== 报表页补充 =====
    '{count} 次 · {tokens} tok': '{count} req · {tokens} tok',
    '{key}：{value} 次': '{key}: {value} req',
    '命中 {hits} / 未命中 {misses} · 命中率 {rate}% · 条目 {entries} · {kb} KB':
        'Hits {hits} / Misses {misses} · Hit rate {rate}% · Entries {entries} · {kb} KB',

    // ===== 模型管理补充 =====
    '{provider}：{count} 个': '{provider}: {count}',
    '{name} {count} 个（新增 {new}）': '{name} {count} (new {new})',

    // ===== 告警（服务层生成，展示于告警中心）=====
    '代理服务已自动恢复': 'Server auto-recovered',
    '代理服务已启动': 'Server started',
    '代理服务已停止': 'Server stopped',
    '代理服务已就绪': 'Server ready',
    '发现新版本 {version}': 'Update available: {version}',
    '每日用量报告 · {name}': 'Daily usage report · {name}',
    '额度耗尽 · {name}': 'Quota exhausted · {name}',
    '额度预警 · {name}': 'Quota warning · {name}',
    '错误率偏高 · {name}': 'High error rate · {name}',
    '触发限流（{dimension}）': 'Rate limited ({dimension})',
    '昨日请求 {n} 次，消耗 {t} token，错误 {e} 次':
        'Yesterday: {n} requests, {t} tokens, {e} errors',
    '今日额度 {q} token 已用尽（{used}），该 key 已退出轮询。':
        'Daily quota {q} tokens exhausted ({used}). Key removed from rotation.',
    '今日额度已使用 {pct}%（{used}/{quota}）':
        'Daily quota used {pct}% ({used}/{quota})',
    '今日错误率 {pct}%（{err}/{req}）':
        "Today's error rate {pct}% ({err}/{req})",
    '来源 {ip} 因「{dim}」被限流：{msg}':
        'Client {ip} rate limited by "{dim}": {msg}',
  };

  /// 取翻译文本
  String t(String key) => language == 'en' ? (_en[key] ?? key) : key;

  /// 静态便捷方法
  static String tr(String key) => instance.t(key);

  /// 带占位符的翻译：`L10n.fmt('确认删除「{name}」？', {'name': k.name})`
  static String fmt(String key, Map<String, String> args) {
    var s = instance.t(key);
    args.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  /// 数量词：中文 "5 个"，英文 "5"
  static String count(int n) =>
      instance.language == 'en' ? '$n' : '$n 个';

  /// 同步语言（来自设置）
  void setLanguage(String lang) => language = lang == 'en' ? 'en' : 'zh';
}
