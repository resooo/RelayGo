# Contributing to RelayGo

感谢你对 RelayGo 的关注！欢迎提交 Issue、PR 或任何形式的改进建议。

> 中文主要用于协作；Issue 与 PR 可用中文或英文撰写。

## 开发环境

- Flutter 3.x（Dart 3.x）
- 大陆环境建议配置镜像后再 `flutter pub get`

## 提交流程

1. Fork 本仓库并创建你的特性分支（`feature/xxx` 或 `fix/xxx`）。
2. 修改代码，并**为改动补充/更新单元测试**（`test/` 目录）。
3. 运行质量门禁，确保全部通过：

   ```bash
   flutter analyze --fatal-infos   # 静态分析（0 issue）
   flutter test                    # 全部单元测试通过
   ```

4. 提交并推送，然后发起 Pull Request，标题注明中文概述与对应需求。

## 代码约定

- 涉及统一模型（`provider:name`）、同步历史、代理 `/v1/models` 的改动，务必运行
  `model_info_test` / `model_repository_test` / `model_sync_service_test` / `proxy_models_test`。
- 新增 UI 文案请同步补充 `lib/l10n/app_strings.dart` 的中英映射。
- 新增依赖请更新 `pubspec.yaml` 与 `THIRD_PARTY_NOTICES.md`。
- 保持提交信息简洁、可读，遵循 Conventional Commits 风格（`feat:` / `fix:` / `docs:` / `chore:`）。

## Issue 模板建议

- **Bug 报告**：平台 / 版本、复现步骤、期望行为、实际现象（附日志）。
- **功能建议**：使用场景、期望能力、可实现的思路。

## 许可证

通过提交 PR，你同意你的贡献在 [AGPL-3.0](LICENSE) 下授权。