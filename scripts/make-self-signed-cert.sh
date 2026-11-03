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
: "${P12_PASSWORD:?用法: P12_PASSWORD='你的密码' ./scripts/make-self-signed-cert.sh [证书名]}"

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
B64="$(base64 -i "$OUT/id.p12" | tr -d '\n')"

cat <<EOF

================ 完成 ================

证书文件：$OUT/id.p12
证书 SHA-1：$SHA1

GitHub Secrets（仓库 Settings → Secrets and variables → Actions）：

  SIGN_CERT_P12_BASE64 = 下面这一整行
$(printf '%s' "$B64" | fold -w 100 | sed 's/^/    /')

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
