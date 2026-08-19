# RelayGo · AI API 中转站

> **Your AI Relay, Ready to Go** — 运行在手机 / 桌面端的 AI API 智能中转与密钥管理器。

RelayGo 在设备本地启动一个与 OpenAI 兼容的轻量 HTTP 网关，统一集中管理多家 AI 服务商的 API Key，并提供负载均衡、失败自动切换、协议转换、限流、响应缓存、额度监控与模型列表同步等能力。第三方 AI 应用只需把 `base_url` 指向 RelayGo，即可共享这一批受管理的高可用 Key。

> 项目开源协议：**AGPL-3.0**。使用前请阅读 [LICENSE](LICENSE) 与 [开源协议](lib/screens/license_screen.dart)。

---

## ✨ 核心特性

- **多提供商接入** — OpenAI / Anthropic / Google / Azure / 自定义，统一适配
- **6 种负载均衡策略** — 轮询、加权轮询、优先级、最少连接、响应时间、智能
- **失败自动切换** — 连续失败自动标记冷却与自动恢复，单请求最多切换 3 个 Key
- **模型列表同步** — 自动拉取各提供商模型、统一格式、能力推断、定时同步
- **响应缓存** — 复用幂等 2xx 响应，降低重复请求成本
- **多维限流** — IP / 全局 / Key / Token 限流，自适应的 TPM（AIMD）动态调整
- **额度与告警** — 额度预警、错误率监控、统计报表、Webhook 通知
- **后台保活** — 前台服务 + 开机自启 + 电池优化白名单
- **Key 安全管理** — AES-256 本地加密、批量测试 / 导入 / 导出、失效自动禁用
- **在线更新** — GitHub Releases + 应用内检查（方案一）

## 🧱 技术栈

| 项 | 说明 |
|---|---|
| 框架 | Flutter 3.x（Dart 3.x） |
| 存储 | Hive 本地加密存储 |
| 加密 | `encrypt`（AES-256）、`crypto`（SHA-256） |
| 状态管理 | `provider` |
| 网络 | `http`（流式 SSE 转发）、`url_launcher` |
| 平台 | Android / iOS / Web / Linux / Windows / macOS |

## 📦 快速开始

```bash
# 1. 安装依赖
flutter pub get

# 2. 中国大陆环境配置镜像（可选）
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# 3. 运行（Android 设备 / 桌面 / Web）
flutter run

# 4. 构建 Release APK
flutter build apk --release

# 5. 质量门禁
flutter analyze && flutter test
```

## 🚀 使用方式

1. 在「Key 管理」中添加各服务商的 API Key（支持批量导入）。
2. 在「模型同步」中拉取可用模型并启用需要的模型。
3. 设置局域网内其他设备可连接的监听端口（默认 `8788`），并把宿主 IP + 端口作为 `base_url` 填入你的 AI 应用。

## 📁 目录结构

```
lib/
├── main.dart            # 入口
├── app.dart             # 全局状态 AppState（装配所有服务）
├── config/              # 常量、主题、环境
├── database/            # Hive 初始化与仓储
├── models/              # 数据模型
├── services/            # 代理、同步、密钥、限流、缓存等
│   └── providers/       # 各服务商适配
├── screens/             # 页面与对话框
├── widgets/             # 复用组件
├── utils/               # 加解密、校验、格式化
└── l10n/                # 多语言字符串
test/                    # 单元测试
```

## 🔒 安全性

- API Key 明文仅在创建时加密、转发时临时解密，存储层与日志层不保留明文。
- 监听服务默认应对局域网开放，生产使用请自行做好访问控制。
- 请遵守各 AI 服务商的使用条款，本项目仅供学习与个人使用。

## 🧩 开源与致谢

RelayGo 使用到的核心开源依赖与参考项目清单，详见应用内「设置 → 开源协议」页面，或查阅 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 📄 许可证

[GNU Affero General Public License v3.0](LICENSE)（AGPL-3.0）

<sub>© 2026 RelayGo Authors</sub>