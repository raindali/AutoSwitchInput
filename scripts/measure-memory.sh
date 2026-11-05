#!/bin/bash
set -euo pipefail

# ============================================
# 常驻内存冒烟测试
#
# 「菜单栏进程不链接 SwiftUI」只是内存目标的代理指标：
# 往 Core 里加一个 NSImage 缓存、一次 eager 枚举，链接检查照样通过，
# 常驻内存却会悄悄涨回去。这里直接量 phys_footprint。
#
# 用法：
#   ./scripts/measure-memory.sh [可执行文件路径]
#   CEILING_MB=25 WAIT_SECONDS=8 ./scripts/measure-memory.sh
#
# 退出码：0 通过 / 1 超限或测量失败
# ============================================

APP="${1:-AutoSwitchInput.app/Contents/MacOS/AutoSwitchInput}"
CEILING_MB="${CEILING_MB:-25}"
WAIT_SECONDS="${WAIT_SECONDS:-8}"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'

if [ ! -x "$APP" ]; then
    echo "  ${RED}✗${RESET} 找不到可执行文件: $APP"
    exit 1
fi

# 已经有实例在跑时测量不可靠（会多一个状态栏图标），直接跳过。
if pgrep -x "$(basename "$APP")" >/dev/null 2>&1; then
    echo "  ${YELLOW}!${RESET} 已有实例在运行，跳过内存测量（先退出再测）"
    exit 0
fi

"$APP" >/dev/null 2>&1 &
PID=$!
cleanup() { kill "$PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# 等它完成启动、建好状态栏图标
sleep "$WAIT_SECONDS"

if ! kill -0 "$PID" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} 进程启动后立即退出，无法测量"
    exit 1
fi

LINE="$(footprint -p "$PID" 2>/dev/null | grep 'phys_footprint:' | head -1 || true)"
MB="$(printf '%s\n' "$LINE" | sed -n 's/.*phys_footprint: \([0-9][0-9]*\) MB.*/\1/p')"
if [ -z "$MB" ]; then
    # 小于 10 MB 时 footprint 改用 KB 输出，正好是最该通过的情况
    KB="$(printf '%s\n' "$LINE" | sed -n 's/.*phys_footprint: \([0-9][0-9]*\) KB.*/\1/p')"
    if [ -n "$KB" ]; then
        MB=$(( (KB + 1023) / 1024 ))
    fi
fi

if [ -z "$MB" ]; then
    echo "  ${RED}✗${RESET} 无法读取 footprint（输出: ${LINE:-空}）"
    exit 1
fi

if [ "$MB" -le "$CEILING_MB" ]; then
    echo "  ${GREEN}✓${RESET} 常驻内存 ${MB} MB（上限 ${CEILING_MB} MB）"
    exit 0
fi

echo "  ${RED}✗${RESET} 常驻内存 ${MB} MB，超过上限 ${CEILING_MB} MB"
exit 1
