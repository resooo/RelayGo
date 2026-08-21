#!/usr/bin/env bash
# RelayGo 编译环境一键恢复脚本（中国大陆环境，全部走国内镜像）
#
# 作用：环境重置后，在本机安装/恢复 Flutter + JDK 17 + Android SDK(API 36)
#       + NDK 28.2.13676358 + Gradle 8.14，并生成 android/local.properties。
# 用法：
#   sudo bash scripts/setup_env.sh
# 可选：FLUTTER_VERSION=3.29.0 bash scripts/setup_env.sh   # 指定 Flutter 版本
#
# 注意：
# - 需要 root 权限写入 /opt。
# - Android 组件较大（NDK 约 1-2GB），首次下载需耐心。
# - android/keystore.properties 不入库，环境重置后需另行恢复（见 ENVIRONMENT.md）。

set -euo pipefail

# —— 可调参数 ——
FLUTTER_VERSION="${FLUTTER_VERSION:-3.29.0}"
FLUTTER_URL="https://storage.flutter-io.cn/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_SDK="/opt/flutter"
ANDROID_SDK="/opt/android-sdk"
ANDROID_PLATFORM="android-36"
ANDROID_BUILD_TOOLS="36.0.0"
ANDROID_NDK="28.2.13676358"
CMDLINE_TOOLS_ZIP="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
GRADLE_VERSION="8.14"

# —— 国内镜像（pub）
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "错误：需要 root 权限写入 /opt。请用 sudo bash scripts/setup_env.sh" >&2
    exit 1
  fi
}

# —— 1. JDK 17 ——
install_jdk() {
  if [[ -d /usr/lib/jvm/java-17-openjdk-amd64 ]] || [[ -d /usr/lib/jvm/java-17-openjdk-arm64 ]]; then
    echo "[JDK] 已存在 JDK 17，跳过。"
  else
    echo "[JDK] 未找到 JDK 17，正在安装 openjdk-17..."
    apt-get update -qq
    apt-get install -y openjdk-17-jdk-headless
  fi
  export JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(which java || echo /usr/lib/jvm/java-17-openjdk-amd64/bin/java)")")")
  echo "[JDK] JAVA_HOME=$JAVA_HOME"
}

# —— 2. Flutter ——
install_flutter() {
  if [[ -x "$FLUTTER_SDK/bin/flutter" ]]; then
    echo "[Flutter] 已存在 $FLUTTER_SDK，跳过下载。"
  else
    echo "[Flutter] 从镜像下载 Flutter $FLUTTER_VERSION (stable)..."
    mkdir -p /opt
    curl -fL "$FLUTTER_URL" -o /tmp/flutter.tar.xz
    echo "[Flutter] 解压中..."
    tar -xf /tmp/flutter.tar.xz -C /opt
    rm -f /tmp/flutter.tar.xz
  fi
  "$FLUTTER_SDK/bin/flutter" --version
}

# —— 3. Android SDK（cmdline-tools + platform + build-tools + NDK）——
install_android_sdk() {
  mkdir -p "$ANDROID_SDK"
  local sdkmanager="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
  if [[ ! -x "$sdkmanager" ]]; then
    echo "[Android] 下载 commandline-tools..."
    mkdir -p "$ANDROID_SDK/cmdline-tools"
    curl -fL "$CMDLINE_TOOLS_ZIP" -o /tmp/cmdtools.zip
    unzip -q -o /tmp/cmdtools.zip -d "$ANDROID_SDK/cmdline-tools"
    mv "$ANDROID_SDK/cmdline-tools/cmdline-tools" "$ANDROID_SDK/cmdline-tools/latest"
    rm -f /tmp/cmdtools.zip
  fi
  export ANDROID_HOME="$ANDROID_SDK"
  export ANDROID_SDK_ROOT="$ANDROID_SDK"
  yes | "$sdkmanager" --licenses >/dev/null 2>&1 || true
  echo "[Android] 安装 platform-tools / platform $ANDROID_PLATFORM / build-tools $ANDROID_BUILD_TOOLS ..."
  "$sdkmanager" \
    "platform-tools" \
    "platforms;$ANDROID_PLATFORM" \
    "build-tools;$ANDROID_BUILD_TOOLS"
  echo "[Android] 安装 NDK $ANDROID_NDK（体积较大，耐心等待...）"
  "$sdkmanager" "ndk;$ANDROID_NDK"
}

# —— 4. 生成 android/local.properties ——
write_local_properties() {
  local lf="/workspace/ai_api_relay_src/android/local.properties"
  if [[ ! -f "$lf" ]]; then
    cat > "$lf" <<EOF
flutter.sdk=$FLUTTER_SDK
sdk.dir=$ANDROID_SDK
flutter.versionName=1.0.1
flutter.versionCode=1
EOF
    echo "[local.properties] 已生成 $lf"
  else
    echo "[local.properties] 已存在，跳过。若路径不对请手动检查 $lf"
  fi
  cat "$lf"
}

# —— 5. 检查签名凭据 ——
check_signing() {
  local kp="/workspace/ai_api_relay_src/android/keystore.properties"
  if [[ -f "$kp" ]]; then
    echo "[签名] keystore.properties 已存在。"
  else
    echo "[签名] 未找到 keystore.properties。"
    echo "        Release 构建将回退 debug 签名（指纹会变）。正式发布请按 ENVIRONMENT.md 恢复该文件。"
  fi
}

main() {
  command -v unzip >/dev/null || { apt-get update -qq && apt-get install -y unzip curl xz-utils; }
  require_root
  install_jdk
  install_flutter
  install_android_sdk
  write_local_properties
  check_signing

  echo ""
  echo "== 工具链恢复完成 =="
  echo "Flutter : $FLUTTER_SDK"
  echo "Android : $ANDROID_SDK"
  echo "JDK     : $JAVA_HOME"
  echo "下一步：cd /workspace/ai_api_relay_src && flutter pub get && flutter build apk --release"
}

main "$@"