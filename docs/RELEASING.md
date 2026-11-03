# 发布流程与隐私说明

本文档说明如何签名、公证并发布 AutoSwitchInput，以及**哪些信息会公开**。
在配置任何凭据之前，请先读第 4 节。

---

## 1. 一次性准备

需要 **Apple Developer Program**（个人 $99/年 或 组织账号）。

| 项目 | 从哪里拿 | 备注 |
|---|---|---|
| Developer ID Application 证书 | Apple Developer → Certificates | 导出为 `.p12` 并设置密码 |
| Team ID | Apple Developer → Membership | 10 位，会公开在签名里 |
| 公证凭据 | Apple ID + **App 专用密码** | 不要用主账号密码 |
| GitHub Secrets | 见下表 | 只放 CI，绝不入库 |

### 需要在 GitHub 仓库配置的 Secrets

| Secret 名称 | 内容 |
|---|---|
| `MACOS_CERT_P12_BASE64` | `base64 -i cert.p12 \| pbcopy` 的结果 |
| `MACOS_CERT_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `KEYCHAIN_PASSWORD` | 临时钥匙串密码，随便生成一个强密码 |
| `NOTARY_APPLE_ID` | 用于公证的 Apple ID |
| `NOTARY_TEAM_ID` | Team ID |
| `NOTARY_PASSWORD` | 上面 Apple ID 的 App 专用密码 |

> Fork 的 PR 拿不到这些 secrets，所以外部贡献者无法触发带签名的发布。

---

## 2. 发布步骤

```bash
# 1. 改版本号
#    Resources/Info.plist: CFBundleShortVersionString / CFBundleVersion

# 2. 更新 CHANGELOG.md

# 3. 自检（会检查凭据泄露、产物隐私、架构约束）
./scripts/release-check.sh

# 4. 提交并打 tag
git commit -am "release: v1.2.3"
git tag v1.2.3
git push origin HEAD --tags
```

推送 tag 后 `.github/workflows/release.yml` 会：

1. 校验 secrets 是否齐全（缺失则直接失败并列出缺哪几个）
2. `swift build -c release` + `swift test`
3. 用 Developer ID 签名（hardened runtime + 时间戳）
4. 提交 Apple 公证，`stapler` 装订票据
5. 打包 `.zip` / `.dmg`，生成 SHA-256
6. 创建 GitHub Release 并上传

发布后验证：

```bash
spctl -a -vv AutoSwitchInput.app     # 应输出 accepted / source=Notarized Developer ID
codesign -dv --verbose=4 AutoSwitchInput.app
```

---

## 3. 本地签名（不打 tag 时）

```bash
SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" ./build.sh
```

不设置 `SIGN_IDENTITY` 时仍是 ad-hoc 签名（本地开发用，无身份信息）。

---

## 4. 哪些信息会公开（重要）

| 内容 | 是否公开 | 说明 |
|---|---|---|
| 证书主体（姓名 / 公司名） | ⚠️ **公开** | 每个下载到 App 的人都能 `codesign -dv` 看到 |
| Team ID | ⚠️ 公开 | 可反查到开发者账号 |
| 公证票据 | ✅ 干净 | 只有哈希，不含身份信息 |
| 签名私钥 `.p12` | ✅ 不公开 | 只在 GitHub Secrets |
| Apple ID / 专用密码 | ✅ 不公开 | 只在 GitHub Secrets |
| 源码 / 二进制内容 | ✅ 干净 | `scripts/release-check.sh` 会检查本机路径与用户名 |

**结论：签名发布必然公开证书上的名字。** 如果不想公开真名，只能：

1. 使用**组织账号**（证书显示公司名，需要 D-U-N-S 编号）；或
2. 保持 ad-hoc 发布，让用户自行编译；或
3. 接受真名公开（多数开源 macOS 应用的做法）。

---

## 5. 安全约定

- **绝不提交**：`*.p12`、`*.cer`、`*.mobileprovision`、`ExportOptions.plist`、任何私钥。
  `.gitignore` 已覆盖，CI 也会拦截。
- CI 日志里不要 `echo` 任何 secret；GitHub 会自动掩码，但不要依赖它。
- 公证使用**独立 App 专用密码**，可随时在 Apple ID 页面吊销。
- 证书泄露时：到 Apple Developer 吊销证书 → 重新签发 → 更新 secret。
- 发布产物只上传 `.zip` / `.dmg`，**不要上传 `.xcarchive`**（内含完整本地路径与 dSYM）。

---

## 6. 自动更新（Sparkle，可选，当前未启用）

如果之后要加 Sparkle：

1. 生成 EdDSA 密钥对：`generate_keys`
2. **公钥**写进 `Info.plist` 的 `SUPublicEDKey`（公开，没问题）
3. **私钥**存进 GitHub Secret `SPARKLE_PRIVATE_KEY`，绝不入库
4. `SUFeedURL` 指向 GitHub Releases 的公开地址，不要用个人域名

当前版本没有引入 Sparkle，保持零第三方依赖。
