#!/bin/bash
set -euo pipefail

# ============================================
# 生成用于本地 / CI 签名的自签名代码签名证书
#
# 用法：
#   P12_PASSWORD='你的密码' ./scripts/make-self-signed-cert.sh ["证书名称"]
#
# 产物在 dist/self-signed/（已被 .gitignore 忽略）：
#   cert.pem   公钥证书
#   key.pem    私钥（用完请删除）
#   id.p12     打包好的证书 + 私钥（用于 GitHub Secret）
#
# 说明：
#   - 自签名证书无法公证，别人下载后仍会被 Gatekeeper 拦截；
#     它的价值是给 App 一个**稳定的签名身份**，让 TCC 授权（输入监控等）
#     在重新编译 / 升级后依然有效。
#   - 证书私钥只应存在于 GitHub Secrets，不要提交、不要上传。
# ============================================

CN="${1:-AutoSwitchInput Self-Signed}"

# 口令不要走命令行：会留在 shell history 与进程参数里（ps 可见）。
# 优先读 P12_PASSWORD_FILE，其次交互输入；都不行就退出。
if [ -z "${P12_PASSWORD:-}" ]; then
    if [ -n "${P12_PASSWORD_FILE:-}" ]; then
        P12_PASSWORD="$(cat "$P12_PASSWORD_FILE")"
    elif [ -t 0 ]; then
        printf 'p12 password: ' >&2
        read -r -s P12_PASSWORD
        printf '\n' >&2
    else
        echo "用法: P12_PASSWORD_FILE=<文件> $0 [证书名]  或交互输入" >&2
        exit 1
    fi
fi
[ -n "$P12_PASSWORD" ] || { echo "口令不能为空" >&2; exit 1; }

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT_DIR:-$PROJECT_DIR/dist/self-signed}"
mkdir -p "$OUT"
chmod 700 "$OUT"

echo "[1/4] 生成私钥与自签名证书（CN=${CN}）..."
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$OUT/key.pem" -out "$OUT/cert.pem" -days 3650 \
    -subj "/CN=$CN" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null

echo "[2/4] 打包为 PKCS#12..."
# macOS 的 security import 只认老的 3DES/SHA1 算法；OpenSSL 3+ 默认用 AES 会导入失败。
if ! openssl pkcs12 -export -legacy \
        -out "$OUT/id.p12" -inkey "$OUT/key.pem" -in "$OUT/cert.pem" \
        -name "$CN" -passout "pass:$P12_PASSWORD" 2>/dev/null; then
    openssl pkcs12 -export \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
        -out "$OUT/id.p12" -inkey "$OUT/key.pem" -in "$OUT/cert.pem" \
        -name "$CN" -passout "pass:$P12_PASSWORD" 2>/dev/null
fi
chmod 600 "$OUT/id.p12" "$OUT/key.pem"

echo "[3/4] 计算证书 SHA-1（用于本地按哈希签名）..."
SHA1="$(openssl x509 -in "$OUT/cert.pem" -noout -fingerprint -sha1 \
    | sed 's/.*=//; s/://g' | tr '[:upper:]' '[:lower:]')"

echo "[4/4] 生成 GitHub Secret 内容..."
# base64 写进 0600 文件，不要打到 stdout（终端回滚区 / 录屏 / 日志都会留下私钥）
base64 -i "$OUT/id.p12" | tr -d '\n' > "$OUT/id.p12.base64"
chmod 600 "$OUT/id.p12.base64"

cat <<EOF

================ 完成 ================

证书文件：$OUT/id.p12
证书 SHA-1：$SHA1

GitHub Secrets（仓库 Settings → Secrets and variables → Actions）：

  SIGN_CERT_P12_BASE64 = 下面文件的内容（不要直接打印到终端）

    cat "$OUT/id.p12.base64" | pbcopy     # 拷到剪贴板后粘贴进 Secret
    # 或：cat "$OUT/id.p12.base64"

  SIGN_CERT_PASSWORD   = 你刚才设置的 P12_PASSWORD
  KEYCHAIN_PASSWORD    = 随便一个新的强密码（CI 里临时钥匙串用）

本地签名（证书需先导入钥匙串）：

  security import "$OUT/id.p12" -k ~/Library/Keychains/login.keychain-db -P '<密码>' -T /usr/bin/codesign
  SIGN_IDENTITY="$SHA1" ./build.sh

======================================
EOF

echo
echo "提示：上传完 Secret 后建议删除私钥文件："
echo "  rm -rf \"$OUT\""
