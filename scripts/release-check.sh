#!/bin/bash
set -euo pipefail

# ============================================
# 发布前自检
#
# 用途：在打 tag / 发版之前，确认「不会泄露个人信息」且产物符合预期。
# 用法：./scripts/release-check.sh
#
# 检查项：
#   1. 仓库里没有签名 / 公证凭据文件，也没有私钥内容
#   2. 工作区干净（避免发出未提交的改动）
#   3. 构建产物里没有本机路径 / 用户名
#   4. 菜单栏进程不链接 SwiftUI（架构约束）
#   5. 本地化资源齐全
#   6. 签名身份是否符合预期（ad-hoc 或 Developer ID）
# ============================================

APP_NAME="AutoSwitchInput"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RES_DIR="$PROJECT_DIR/Resources"
cd "$PROJECT_DIR"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
FAILED=0

pass() { echo "  ${GREEN}✓${RESET} $1"; }
warn() { echo "  ${YELLOW}!${RESET} $1"; }
fail() { echo "  ${RED}✗${RESET} $1"; FAILED=1; }

echo "${BOLD}== 1. 凭据泄露检查 ==="
# 凭据规则只维护在 .gitignore 的凭据段，这里把它转成正则，避免两份清单漂移。
# （不能直接用 `git check-ignore`：那会把备份 / 图标源等历史产物也算进来。）
SECRET_PATTERN="$(awk '
    /^# 签名 \/ 公证凭据/ { inblock = 1; next }
    inblock && NF == 0    { inblock = 0 }
    inblock && /^#/       { next }
    inblock {
        glob = $0
        if (glob ~ /\/$/) {
            sub(/\/$/, "", glob); sub(/^\*/, "", glob)
            gsub(/\./, "\\.", glob)
            printf "%s(/|$)|", glob
        } else if (glob ~ /^\*\./) {
            sub(/^\*/, "", glob)
            gsub(/\./, "\\.", glob)
            printf "%s$|", glob
        } else if (glob ~ /^\*/) {
            sub(/^\*/, "", glob)
            gsub(/\./, "\\.", glob)
            printf "%s", glob
        } else if (glob ~ /\*$/) {
            sub(/\*$/, "", glob)
            gsub(/\./, "\\.", glob)
            printf "%s", glob
        } else {
            gsub(/\./, "\\.", glob)
            printf "(^|/)%s$|", glob
        }
    }
' .gitignore | sed 's/|$//')"

SECRET_FILES="$(git ls-files | grep -E "$SECRET_PATTERN" || true)"
if [ -n "$SECRET_FILES" ]; then
    fail "仓库里有凭据类文件被跟踪："
    echo "$SECRET_FILES" | sed 's/^/      /'
else
    pass "没有被跟踪的签名 / 公证凭据文件"
fi

if git grep -I -q -E 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'; then
    fail "仓库里出现了私钥内容（BEGIN ... PRIVATE KEY）"
else
    pass "工作树里没有私钥内容"
fi

# 只看工作树不够：提交过又被删掉的凭据仍会随仓库分发（公开仓库尤其致命）。
HISTORY_FILES="$(git rev-list --all --objects 2>/dev/null | awk 'NF > 1 {print $2}' \
    | grep -E "$SECRET_PATTERN" | sort -u || true)"
if [ -n "$HISTORY_FILES" ]; then
    fail "git 历史里出现过凭据类文件（即使已删除仍可被 clone 到）："
    printf '%s\n' "$HISTORY_FILES" | head -5 | sed 's/^/      /'
else
    pass "git 历史里没有凭据类文件"
fi

# 注意两点：
#   1. pickaxe 的字符串不要写全，否则本脚本自己会被上面的 grep 命中；
#   2. 本脚本自身也被排除，否则「添加这个守卫」的那次提交会命中自己。
HISTORY_KEYS="$(git log --all --oneline \
    -S'BEGIN RSA PRIVATE' -S'BEGIN PRIVATE' -S'BEGIN OPENSSH PRIVATE' \
    -- . ':!scripts/release-check.sh' 2>/dev/null | head -3 || true)"
if [ -n "$HISTORY_KEYS" ]; then
    fail "git 历史里出现过私钥内容："
    printf '%s\n' "$HISTORY_KEYS" | sed 's/^/      /'
else
    pass "git 历史里没有私钥内容"
fi

echo
echo "${BOLD}== 2. 工作区状态 ==="
if [ -n "$(git status --porcelain)" ]; then
    warn "工作区有未提交的改动，发布前请确认："
    git status --short | sed 's/^/      /'
else
    pass "工作区干净"
fi

# tag 与版本号不一致时发布出的资产名会与 app 自报版本对不上
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$RES_DIR/Info.plist" 2>/dev/null || echo "?")"
EXACT_TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
if [ -n "$EXACT_TAG" ] && [ "v${PLIST_VERSION}" != "$EXACT_TAG" ]; then
    fail "HEAD 上的 tag 是 $EXACT_TAG，但 Info.plist 版本是 $PLIST_VERSION"
fi

echo
echo "${BOLD}== 3. 构建 ==="
swift test >/dev/null 2>&1 || { fail "swift test 失败"; exit 1; }
pass "编译与测试通过"
./build.sh --no-install >/dev/null 2>&1 || { fail "打包失败"; exit 1; }
pass "打包成功"

echo
echo "${BOLD}== 4. 产物隐私检查 ==="
LOCAL_USER="$(whoami)"
# 落临时文件而不是塞进变量：两个二进制的字符串表有数 MB，回灌 grep 会把负载复制两份
STRINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/asi-strings.XXXXXX")"
trap 'rm -f "$STRINGS_FILE"' EXIT
strings -a "$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    "$APP_NAME.app/Contents/MacOS/${APP_NAME}Settings" > "$STRINGS_FILE" 2>/dev/null || true
if grep -q -E "/Users/|/home/" "$STRINGS_FILE"; then
    fail "二进制里含有本机路径，发布前需要确认："
    grep -E "/Users/|/home/" "$STRINGS_FILE" | sort -u | head -5 | sed 's/^/      /'
elif grep -qF "$LOCAL_USER" "$STRINGS_FILE"; then
    # 只警告：CI runner 的用户名（runner）可能恰好是某些字符串的子串
    warn "二进制里出现了当前用户名（${LOCAL_USER}），请确认不是路径泄露"
else
    pass "二进制里没有本机路径 / 用户名"
fi

echo
echo "${BOLD}== 4b. 常驻内存 ==="
if [ -x "$PROJECT_DIR/scripts/measure-memory.sh" ]; then
    if ! "$PROJECT_DIR/scripts/measure-memory.sh" "$APP_NAME.app/Contents/MacOS/$APP_NAME"; then
        FAILED=1
    fi
else
    warn "缺少 scripts/measure-memory.sh，跳过内存测量"
fi

echo
echo "${BOLD}== 5. 架构与资源约束 ==="
MENU_LIBS="$(otool -L "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true)"
SETTINGS_LIBS="$(otool -L "$APP_NAME.app/Contents/MacOS/${APP_NAME}Settings" 2>/dev/null || true)"
case "$MENU_LIBS" in
    *SwiftUI*) fail "菜单栏进程链接了 SwiftUI（会带回常驻内存开销）" ;;
    *)         pass "菜单栏进程不链接 SwiftUI" ;;
esac
case "$SETTINGS_LIBS" in
    *SwiftUI*) pass "设置进程链接 SwiftUI" ;;
    *)         fail "设置进程没有链接 SwiftUI，构建可能不完整" ;;
esac
for lproj in en zh-Hans; do
    if [ -f "$APP_NAME.app/Contents/Resources/$lproj.lproj/Localizable.strings" ]; then
        pass "$lproj 本地化资源齐全"
    else
        fail "缺少 $lproj.lproj/Localizable.strings"
    fi
done

echo
echo "${BOLD}== 6. 签名 ==="
SIGN_INFO="$(codesign -dv "$APP_NAME.app" 2>&1 || true)"
printf '%s\n' "$SIGN_INFO" | sed -n 's/^Authority=/      身份: /p' || true
case "$SIGN_INFO" in
    *"Signature=adhoc"*)
        warn "当前是 ad-hoc 签名：不含任何身份信息，但用户首次打开会被 Gatekeeper 拦截"
        ;;
    *)
        warn "非 ad-hoc 签名：证书里的姓名 / Team ID 会随 App 公开分发，确认可以接受后再发布"
        ;;
esac

echo
if [ "$FAILED" -eq 0 ]; then
    echo "${GREEN}${BOLD}自检通过${RESET}"
    echo
    echo "发布清单（详见 docs/RELEASING.md）："
    echo "  1. 更新 Resources/Info.plist 的 CFBundleShortVersionString / CFBundleVersion"
    echo "  2. 更新 CHANGELOG.md"
    echo "  3. git tag vX.Y.Z && git push --tags"
    echo "  4. 等待 release workflow 完成签名 / 公证 / 上传"
    echo "  5. 下载产物跑一遍：spctl -a -vv AutoSwitchInput.app"
else
    echo "${RED}${BOLD}自检未通过${RESET}"
    exit 1
fi
