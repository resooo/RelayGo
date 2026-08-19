#!/usr/bin/env bash
# RelayGo -> GitHub 一键同步脚本
#
# 用法（任选其一）：
#   1) 直接填入 TOKEN 后运行：
#        GITHUB_TOKEN=ghp_xxxx sh github_sync.sh
#
# 先决条件：仓库已初始化并提交（当前在 main 分支，工作区干净）。
set -e

REPO="resooo/RelayGo"
REMOTE_URL="https://github.com/${REPO}.git"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "错误：未提供 GITHUB_TOKEN。请先设置有效 Token 后重试。" >&2
  echo "  例如：GITHUB_TOKEN=ghp_你的令牌 sh github_sync.sh" >&2
  exit 1
fi

AUTH_URL="https://resooo:${GITHUB_TOKEN}@github.com/${REPO}.git"

echo ">> 检查远端是否可达（使用提供的 Token）..."
if git ls-remote "${AUTH_URL}" >/dev/null 2>&1; then
  echo "   Token 有效，远端可达。"
else
  echo "   Token 无效或没有权限（GitHub 返回认证失败）。"
  echo "   请在 GitHub：头像 -> Settings -> Developer settings -> Personal access tokens"
  echo "   生成一个 token，勾选 repo（或 Contents: write + Metadata: read），再重试。"
  exit 1
fi

echo ">> 设置远端并推送 main 分支..."
git remote set-url origin "${AUTH_URL}"
git push -u origin main

# 推送后把远端地址还原成不含 token 的安全形式，避免令牌泄露进配置
git remote set-url origin "${REMOTE_URL}"

echo ">> 完成：已同步到 https://github.com/${REPO}"