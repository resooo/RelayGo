# RelayGo 编译环境要求

本文档说明 RelayGo v1.0.1 在 Linux（Ubuntu 22.04）上编译 Android Release 所需的全部环境组件与版本。用于环境重置后快速恢复，可配合 `scripts/setup_env.sh` 一键安装。

## 版本要求总览

| 组件 | 版本 | 说明 |
|---|---|---|
| Flutter | 3.x（Dart SDK `>=3.0.0 <4.0.0`） | 见 `pubspec.yaml` |
| Dart | 随 Flutter 提供 | 无需单独安装 |
| JDK | **17** | `build.gradle` 指定 `VERSION_17`，JDK 11 不满足 |
| Android SDK | compileSdk / targetSdk **36** | `android/app/build.gradle` |
| Android NDK | **28.2.13676358** | 已在 `build.gradle` 全局固定 |
| Android Gradle Plugin | 8.11.1 | `android/settings.gradle` |
| Kotlin | 2.2.20 | `android/settings.gradle` |
| Gradle | 8.14 | `gradle-wrapper.properties` 指向本地 zip |

## Flutter 依赖（pubspec.yaml）

核心运行库：`hive`、`hive_flutter`、`encrypt 5.0.1`、`provider`、`http`、`crypto`、`intl`、`file_selector`、`url_launcher`、`cupertino_icons`。

测试与分析：`flutter_test`、`flutter_lints`（`analysis_options.yaml` 启用）。

必须保留的依赖覆盖（兼容新版 Flutter/AGP）：`path_provider_windows 2.3.0`、`path_provider 2.1.6`、`path_provider_android 2.2.23`。删除会导致编译失败。

## Android 签名

- 密钥库：`android/keystore/relaygo-release.jks`（随仓库保留，已入库，保证环境重置后签名指纹一致）。
- 凭据：`android/keystore.properties`（**不入库**，属 .gitignore；缺失时构建自动回退 debug 签名）。
- 环境重置或新克隆后，需重建此文件：

```properties
RELEASE_STORE_FILE=../keystore/relaygo-release.jks
RELEASE_STORE_PASSWORD=<你的强口令>
RELEASE_KEY_ALIAS=relaygo
RELEASE_KEY_PASSWORD=<你的强口令>
```

## 国内镜像配置

依赖与插件仓库已在 `android/settings.gradle`、`android/build.gradle` 配置阿里云镜像。Flutter 依赖建议使用：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

Android SDK 组件从 `dl.google.com` 下载（国内直连可用，首次拉取较大，需耐心）。

## 目录约定

脚本与仓库按以下路径约定，改动会影响 `android/local.properties` 的生成：

| 项 | 路径 |
|---|---|
| Flutter SDK | `/opt/flutter` |
| Android SDK | `/opt/android-sdk` |
| Gradle 本地发行包 | `/opt/gradle-8.14` |
| local.properties | `android/local.properties`（`flutter.sdk`、`sdk.dir`、版本号） |

## 恢复步骤

1. 运行 `scripts/setup_env.sh`（root 权限，装齐工具链并生成 local.properties）。
2. 检查/重建 `android/keystore.properties`（若未在环境中保留）。
3. `flutter pub get` 拉取依赖。
4. 构建：`flutter build apk --release`（产物在 `build/app/outputs/flutter-apk/app-release.apk`）。
5. 质量门禁（可选）：`flutter analyze && flutter test`。