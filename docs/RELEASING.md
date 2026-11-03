# 发布流程与隐私说明

本文档说明如何签名、公证并发布 AutoSwitchInput，以及**哪些信息会公开**。
在配置任何凭据之前，请先读第 6 节。

---

## 0. 快速开始（fork 仓库）

本仓库的发布流程已配好，第一次发布只需三步：

**① 生成自签名证书**（本机执行一次）

```bash
P12_PASSWORD='给 p12 设的强密码' ./scripts/make-self-signed-cert.sh
```

**② 配置 3 个 Secrets**（仓库 Settings → Secrets and variables → Actions）

| Secret | 值 |
|---|---|
| `SIGN_CERT_P12_BASE64` | 脚本输出的那一整行 base64 |
| `SIGN_CERT_PASSWORD` | 上面的 `P12_PASSWORD` |
| `KEYCHAIN_PASSWORD` | 随便一个新的强密码（CI 临时钥匙串用） |

配置完成后删除本地私钥：`rm -rf dist/self-signed`

**③ 打 tag 发布**

```bash
./scripts/release-check.sh          # 自检
git tag v1.1.0
git push origin v1.1.0
```

Actions 页面能看到 `Release` 工作流；完成后 Releases 里会出现
`AutoSwitchInput-1.1.0.zip`、`.dmg` 和 `SHA256SUMS.txt`。

> Fork 仓库如果提示工作流被禁用：Settings → Actions → General →
> 选择 **Allow all actions and reusable workflows**。

---

## 1. 三种签名模式

发布工作流会根据配置的 secrets 自动选择模式：

| 模式 | 需要什么 | Gatekeeper | 公证 | 签名身份稳定 | 适用 |
|---|---|---|---|---|---|
| **ad-hoc** | 什么都不配 | ❌ 拦截 | ❌ | ❌ 每次重编译都变 | 零配置，自用 |
| **自签名** | 一张自签名证书（免费） | ❌ 拦截 | ❌ | ✅ 证书指纹 | 免费分发 |
| **Developer ID** | 付费开发者账号 | ✅ 直接打开 | ✅ | ✅ Team ID | 正式分发 |

「签名身份稳定」的含义：TCC 授权（输入监控 / 辅助功能）按签名身份记录。
ad-hoc 签名的身份只有 CDHash，重新编译就变 → 用户每次升级都要重新授权；
自签名和 Developer ID 的身份基于证书 → 升级后授权保留。

---

## 2. 一次性准备

### 模式 A：ad-hoc（零配置）

什么都不用做。推送 tag 就会构建并发布未签名版本，用户需手动放行。

### 模式 B：自签名（免费，推荐）

```bash
P12_PASSWORD='给 p12 设的密码' ./scripts/make-self-signed-cert.sh
```

脚本会生成 `dist/self-signed/id.p12`，并打印需要填进 GitHub 的 secrets。
在仓库 **Settings → Secrets and variables → Actions** 配置：

| Secret 名称 | 内容 |
|---|---|
| `SIGN_CERT_P12_BASE64` | 脚本输出的那一整行 base64 |
| `SIGN_CERT_PASSWORD` | 上面设置的 `P12_PASSWORD` |
| `KEYCHAIN_PASSWORD` | 随便一个新的强密码（CI 临时钥匙串用） |

上传后删除本地私钥：`rm -rf dist/self-signed`。

### 模式 C：Developer ID（付费，$99/年）

| Secret 名称 | 内容 |
|---|---|
| `SIGN_CERT_P12_BASE64` | Developer ID 证书的 base64 |
| `SIGN_CERT_PASSWORD` | 导出 p12 时设置的密码 |
| `KEYCHAIN_PASSWORD` | 临时钥匙串密码 |
| `NOTARY_APPLE_ID` | 用于公证的 Apple ID |
| `NOTARY_TEAM_ID` | Team ID |
| `NOTARY_PASSWORD` | 上面 Apple ID 的 **App 专用密码** |

只要 `NOTARY_PASSWORD` 存在就按 Developer ID 模式处理（含公证）。

---

## 3. 发布步骤

```bash
# 1. 改版本号：Resources/Info.plist 的 CFBundleShortVersionString / CFBundleVersion
# 2. 更新 CHANGELOG.md
# 3. 自检（凭据泄露 / 产物隐私 / 架构约束）
./scripts/release-check.sh
# 4. 打 tag
git commit -am "release: v1.2.3"
git tag v1.2.3
git push origin HEAD --tags
```

`release.yml` 会：测试 → 自检 → 按模式签名 → （Developer ID 时）公证 → 打包 zip/dmg + SHA256 → 建 GitHub Release。

想先演练一次不发布：在 Actions 里手动 **Run workflow**，产物会作为 artifact 上传，不会创建 Release。

发布后验证：

```bash
spctl -a -vv AutoSwitchInput.app          # Developer ID 应输出 accepted
codesign -d -r- AutoSwitchInput.app       # 看签名要求
```

---

## 4. 自签名证书的细节

**它解决什么**

- 给 App 一个**稳定的签名身份**：`identifier "com.qingwei.inputswitch" and certificate leaf = H"…"`
- 用户升级新版本后，输入监控 / 辅助功能授权不会被重置

**它不解决什么**

- Gatekeeper 仍然拦截（证书不是 Apple 信任链的一部分），用户需手动放行
- 不能公证
- `spctl -a` 会返回 rejected，这是预期行为

**为什么 CI 里要用 SHA-1 而不是证书名**

自签名证书默认不受信任，`codesign -s "证书名"` 会报 `no identity found`。
用 `security find-identity <keychain>` 拿到 SHA-1，再 `codesign -s <SHA-1> --keychain <keychain>`
就能签（不需要 `sudo` 把证书加入信任列表）。

**本地使用**

```bash
security import dist/self-signed/id.p12 -k ~/Library/Keychains/login.keychain-db \
  -P '<密码>' -T /usr/bin/codesign
SIGN_IDENTITY='<证书 SHA-1>' ./build.sh
```

---

## 5. 本地签名

```bash
# Developer ID（需已导入钥匙串）
SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" SIGN_HARDENED=1 ./build.sh

# 自签名
SIGN_IDENTITY='<SHA-1>' SIGN_KEYCHAIN='<keychain>' ./build.sh

# 不设置 → ad-hoc
./build.sh
```

---

## 6. 哪些信息会公开（重要）

| 内容 | ad-hoc | 自签名 | Developer ID |
|---|---|---|---|
| 证书主体 | 无 | **你自定义的名字** | ⚠️ 真实姓名 / 公司名 |
| Team ID | 无 | 无 | ⚠️ 公开 |
| 公证票据 | 无 | 无 | ✅ 只有哈希 |
| 签名私钥 | 无 | 只在 Secrets | 只在 Secrets |
| Apple ID / 专用密码 | 无 | 无 | 只在 Secrets |

**结论：**

- **ad-hoc**：零身份信息，但用户每次升级要重新授权。
- **自签名**：证书名可以随便起（如 `AutoSwitchInput Dev`），**不暴露真名**，
  同时获得稳定的签名身份。免费方案里隐私与体验最平衡。
- **Developer ID**：必然公开证书上的真实姓名或公司名（个人账号无法用假名）。
  不想暴露真名只能用组织账号（需 D-U-N-S）。

---

## 7. 安全约定

- **绝不提交**：`*.p12`、`*.cer`、`*.mobileprovision`、`ExportOptions.plist`、任何私钥。
  `.gitignore` 已覆盖，CI 也会拦截。
- CI 日志里不要 `echo` 任何 secret。
- 公证使用**独立 App 专用密码**，可随时在 Apple ID 页面吊销。
- 证书泄露时：吊销证书 → 重新签发 → 更新 secret。
- 发布产物只上传 `.zip` / `.dmg`，**不要上传 `.xcarchive`**（内含本地路径与 dSYM）。
- 自签名私钥同样敏感：拿到它的人可以冒充你的 App 签名。

---

## 8. 自动更新（Sparkle，可选，当前未启用）

1. 生成 EdDSA 密钥对：`generate_keys`
2. **公钥**写进 `Info.plist` 的 `SUPublicEDKey`（公开）
3. **私钥**存进 GitHub Secret `SPARKLE_PRIVATE_KEY`，绝不入库
4. `SUFeedURL` 指向 GitHub Releases 的公开地址，不要用个人域名

当前版本没有引入 Sparkle，保持零第三方依赖。

---

## 9. 发布检查清单

发布前：

- [ ] `Resources/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion` 已递增
- [ ] `CHANGELOG.md` 已把「未发布」内容归到新版本下
- [ ] `./scripts/release-check.sh` 全绿
- [ ] `swift test` 全绿
- [ ] 本地跑一遍：打开设置、改规则、切换 App 验证输入法跟随

发布后：

- [ ] Actions 里 `Release` 工作流成功
- [ ] Releases 里三个产物齐全（zip / dmg / SHA256SUMS.txt）
- [ ] 下载 zip 解压后能打开（未签名版本需手动放行）
- [ ] `codesign -d -r- AutoSwitchInput.app` 显示的是预期身份
- [ ] Release 说明里包含安装与授权步骤
