#!/bin/bash
set -euo pipefail

# ============================================
# Build script for AutoSwitchInput
# Builds with SwiftPM, assembles a macOS .app
# bundle (menu bar app + settings helper),
# then deploys a copy to /Applications.
#
# 用法：
#   ./build.sh            # 构建并安装到 /Applications
#   ./build.sh --no-install  # 只构建，不安装
# ============================================

APP_NAME="AutoSwitchInput"
SETTINGS_NAME="${APP_NAME}Settings"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
RES_DIR="$PROJECT_DIR/Resources"
BUNDLE_DIR="$PROJECT_DIR/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"
DO_INSTALL=1

if [[ "${1:-}" == "--no-install" ]]; then
    DO_INSTALL=0
fi

echo "=========================================="
echo "  Building $APP_NAME"
echo "=========================================="

# --- 1. Compile (SwiftPM) ---
echo "[1/5] Compiling (swift build -c release)..."
cd "$PROJECT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
echo "  -> Compiled successfully ($BIN_DIR)"

# --- 2. Prepare bundle structure ---
echo "[2/5] Creating .app bundle structure..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# 菜单栏进程与设置进程是两个独立可执行文件：
# 前者只链接 Core（不含 SwiftUI），后者才链接 SwiftUI，关窗即退出。
cp "$BIN_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/$SETTINGS_NAME" "$BUNDLE_DIR/Contents/MacOS/$SETTINGS_NAME"
echo "  -> Executables copied"

# --- 3. Copy Info.plist / icon ---
echo "[3/5] Copying Info.plist..."
cp "$RES_DIR/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"

if [ -f "$RES_DIR/AppIcon.icns" ]; then
    cp "$RES_DIR/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
    echo "  -> App icon copied"
fi

# --- 4. Code sign (ad-hoc) ---
echo "[4/5] Code signing (ad-hoc)..."
codesign --force --deep --sign - "$BUNDLE_DIR"

if [ "$DO_INSTALL" -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "  Build complete (not installed)"
    echo "  Output: $BUNDLE_DIR"
    echo "=========================================="
    exit 0
fi

# --- 5. Deploy to /Applications ---
echo "[5/5] Deploying to /Applications..."
if [ -d "$INSTALL_PATH" ]; then
    # 若安装副本正在运行，先退出，避免覆盖运行中的应用
    if pgrep -f "$INSTALL_PATH/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
        echo "  -> Quitting running instance..."
        pkill -f "$INSTALL_PATH/Contents/MacOS/$APP_NAME"
        sleep 0.5
    fi
    pkill -f "$INSTALL_PATH/Contents/MacOS/$SETTINGS_NAME" >/dev/null 2>&1 || true
    rm -rf "$INSTALL_PATH"
fi
cp -R "$BUNDLE_DIR" "$INSTALL_PATH"
# 拷贝后签名保持不变（ad-hoc 签名基于内容哈希，内容未变则无需重签，
# 避免 CDHash 变化导致已授予的 TCC 权限（如完整磁盘访问）被重置）
echo "  -> Installed at $INSTALL_PATH"

echo ""
echo "=========================================="
echo "  Build complete!"
echo "  Output:   $BUNDLE_DIR"
echo "  Installed: $INSTALL_PATH"
echo "=========================================="
echo ""
echo "To run:"
echo "  open '$INSTALL_PATH'"
echo ""
echo "If macOS blocks the app, go to:"
echo "  System Settings > Privacy & Security > Allow Anyway"
