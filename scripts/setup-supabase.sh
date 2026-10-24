#!/usr/bin/env bash
# 本地 Supabase 后端一键初始化（T0.4）
#
# 前置：Docker Desktop 已安装并正在运行
#   brew install --cask docker
#
# 用法：
#   bash scripts/setup-supabase.sh          # 初始化 + 启动 + 生成类型
#   bash scripts/setup-supabase.sh reset    # 重建库并重新灌种子数据
#
# Supabase CLI 版本固定为 2.122.0（brew 安装）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SUPABASE_VERSION="2.122.0"
MODE="${1:-start}"

# 1. CLI
if ! command -v supabase >/dev/null 2>&1; then
  echo "==> 安装 Supabase CLI ${SUPABASE_VERSION}"
  brew install supabase/tap/supabase
else
  echo "==> Supabase CLI 已安装：$(supabase --version | head -1)"
fi

# 2. Docker
if ! docker info >/dev/null 2>&1; then
  echo "!! Docker 未运行。请先安装并启动 Docker Desktop："
  echo "     brew install --cask docker"
  echo "   然后打开 Docker.app 等它跑起来，再重跑本脚本。"
  exit 1
fi

# 3. supabase/ 配置（只需一次）
if [ ! -f supabase/config.toml ]; then
  echo "==> supabase init"
  supabase init
fi

# 4. 启动本地栈
echo "==> supabase start"
supabase start

# 5. 应用迁移 + 种子
echo "==> supabase db reset"
supabase db reset

# 6. 生成 TypeScript 数据库类型
echo "==> 生成 database.types.ts"
mkdir -p apps/mobile/src/lib
supabase gen types typescript --local > apps/mobile/src/lib/database.types.ts
echo "==> 已写入 apps/mobile/src/lib/database.types.ts"

echo
echo "完成。本地后台地址："
supabase status | sed -n '1,20p'
