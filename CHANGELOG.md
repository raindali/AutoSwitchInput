# 更新日志

本项目所有值得注意的变更均记录于此。

本文件格式遵循 [Keep a Changelog](https://keepachangelog.com/)，项目以 GPLv3 开源。

---

## [1.2.0] — 2026-11-05

### 新增

- **默认输入法与恢复策略拆成两项**（参考 InputSourcePro）：
  - 「默认输入法」适用于所有没有规则的 App，可选「不切换」或某个具体输入源；
  - 「输入法恢复策略」决定切换回 App 时的行为：总是切到默认输入法，或恢复该 App 上次使用的输入法（没有记录时回落到默认值）。
  - 规则仍然优先；没有快照时按全新安装处理（默认「恢复上次」）。记忆表只由菜单栏进程维护（最近 200 个 App），已失效的输入源会被忽略。

## [1.2.1] — 2026-11-05

### 变更

- **不再兼容 v1.1.x 的设置快照**（v1.1.1 的发布已撤回）：升级后会重置一次，规则回到默认；v1.0 的散装 key 仍会迁移。
- 默认输入法 / 输入法恢复策略的行为与 1.2.0 相同。

## [1.1.1] — 2026-11-05

### 修复

- **默认规则不再指向未启用的输入源**：首次安装时从当前已启用的输入源里挑英文布局（ABC → U.S. → 任意）与中文输入法（简体拼音 → 任意），不再写死 `com.apple.keylayout.ABC`。此前在启用 U.S. 布局的机器上（例如 zh_SG 环境），5 条默认规则会静默失效（`TISSelectInputSource` 返回 -50），只有系统日志里能看到「切换输入法失败」。
- **失效输入源在设置里可见**：规则行与默认输入源下拉在输入源已被系统移除时显示橙色警告与「%@（不可用）」，提示重新选择，不再让规则看起来生效但实际不动作。

### 维护

- **代码简化**：删除死代码与未使用的设计 token、去掉重复的跨进程契约字符串与 `@State` 副本、合并重复的发布步骤，测试改为可观测断言（reload 不回写、同 App 去重）与表驱动，36 → 32 个测试但覆盖不减。
- **CI 凭据扫描**：改为从 `.gitignore` 的凭据段生成正则，只匹配凭据类文件；此前会把历史备份与图标源误报为凭据。

### 修复（代码评审发现）

- **签名私钥收敛**：`security import` 从 `-A` 改为 `-T /usr/bin/codesign`，并在签名步骤后立刻销毁临时钥匙串；此前发布 job 内任何后续步骤（含第三方 action）都能免提示使用签名身份。
- **跨进程同步改为快照直传**：`DistributedNotificationCenter` 的 `userInfo` 直接携带新快照，接收方不再二次读盘——两条 XPC 通道没有顺序保证，重读可能拿到旧值而静默放弃。
- **设置收成单个 `Codable` 快照**：`save()` 与 `reloadFromDefaults()` 不再各自维护一份手写字段列表，新增设置不会漏同步；1.0 的四个散装 key 自动迁移并在首次保存时清理。
- **升级不再丢默认规则**：没有快照时统一补种（覆盖「1.0 从未落盘规则」的升级场景），用户主动删空则不会被重新播种。
- **改完规则立即生效**：`RuleStore.onRemoteChange` 回调让菜单栏进程重放当前前台 App 的规则，不必切走再切回来。
- **输入源决策抽到 Core**：`RuleStore.targetInputSourceID(for:)` 覆盖「规则命中 / 默认兜底 / 总开关关闭 / 两者皆无」四种分支，并补表驱动测试。
- **设置进程缺失有可见反馈**：拉起失败时弹 NSAlert（新增 en / zh-Hans 文案），不再静默无反应；`terminationHandler` 校验进程身份，避免迟到回调清掉新引用。
- **发布幂等**：`gh release view` 命中则 `upload --clobber`，校验和最后上传；tag 与 `Info.plist` 版本不一致直接失败。
- **CI 去重**：`ci.yml` 改为只调 `./scripts/release-check.sh`；凭据 pattern 抽成单一常量并补 `.p8` / `.xcarchive`。
- **证书脚本不再打印私钥**：口令改为文件或交互输入（不进 argv / shell history），base64 写入 0600 文件；文档更正「自签名证书可吊销」的错误说法。
- **UI 小修**：图标缓存降采样到 72×72 并设 64 条上限；规则列表改 `LazyVStack`；`SettingsView` / `HeaderView` 支持注入 `RuleStore`；补上此前从未发射的 `Log.monitor` / `Log.settings`；修正「同一二进制副本」的过时注释。
- **常驻内存冒烟**：`scripts/measure-memory.sh` 启动真实二进制并断言 `phys_footprint` 低于上限（默认 25 MB），接进 `release-check.sh` 与 CI——此前「内存不反弹」只有「不链接 SwiftUI」这一条间接证据。
- **凭据历史扫描**：除工作树外，还扫 `git rev-list --all` 的文件名与 pickaxe，提交过又被删掉的私钥同样会被拦下。
- **发布说明可验证**：Release 正文追加本次构建的 `codesign -d -r-` 期望输出，用户可自行比对签名身份，而不只是信同源的 `SHA256SUMS.txt`。

## [1.1.0] — 2026-11-03

### 性能 / 内存
- **设置窗口拆分为独立进程**：菜单栏进程只负责状态栏图标、右键菜单与前台应用监听，**不链接 SwiftUI**；点开设置时拉起独立可执行文件 `AutoSwitchInputSettings`，关窗即退出。这样「开过一次设置」不会再把 SwiftUI 的视图图与渲染缓存（约 20 MB）永久留在常驻进程里。实测常驻进程稳定在 **12 MB**，设置进程 32 MB 且随窗口关闭消失。
- **规则跨进程同步**：两个进程通过 `DistributedNotificationCenter` + `UserDefaults` 双向同步规则与开关状态，设置里改了规则，菜单栏进程立即生效（登录项注册仍由菜单栏进程负责）。
- **修复启动即弹窗导致的内存占用**：`applicationShouldOpenUntitledFile` 之前会调用 `showSettings()`，而 AppKit 在「无文稿应用」被启动时会询问该方法，于是应用一启动就建好了整个设置窗口。改为返回 `false` 后，菜单栏常驻进程空闲内存从 **~33 MB 降到 ~12 MB**。
- **关闭设置窗口即释放全部 SwiftUI 资源**：设置进程随窗口关闭直接退出，AttributeGraph / DisplayList / 图标与文字缓存一并还给系统，重新打开时再按需拉起。
- **状态栏菜单改为按需构建**：原来每次前台应用切换都会重建整份 `NSMenu`（并顺带枚举输入法），菜单此时并不可见。现在只在右键真正弹出菜单时生成。
- **⌘W 监听不再常驻**：只存在于设置进程内，随进程退出。
- **忽略自身进程的前台激活事件**：打开设置窗口时，「当前应用」不会再变成 AutoSwitchInput 自己。
- **`getCurrentInputSourceID()` 改用 `TISCopyCurrentKeyboardInputSource()`**：不再每次枚举全部输入源建 `CFArray`。
- **应用图标加缓存**：规则行重绘时不再反复走 LaunchServices 查找 + 读盘。
- **「添加规则」的运行中应用列表改为打开时抓一次快照**：不再每次重绘都枚举全部进程。
- **前台应用切换防抖改用一次性 `DispatchWorkItem`**：不再注册 `RunLoop` Timer 源。

### 工程化
- **SwiftPM 化**：拆成 `AutoSwitchInputCore`（规则/输入源/监听，纯逻辑）、`AutoSwitchInputUI`（SwiftUI 界面）、`AutoSwitchInput`（菜单栏进程）、`AutoSwitchInputSettings`（设置进程）四个 target。菜单栏二进制不再链接 SwiftUI，体积 1.05 MB → **238 KB**。
- **单元测试**：新增 23 个 XCTest，覆盖规则持久化与跨进程同步、输入源筛选（类别/启用/父容器/去重/排序）、前台应用防抖；`swift test` 可直接运行。
- **CI**：GitHub Actions 执行「构建 → 测试 → 打包」，并校验「菜单栏进程不链接 SwiftUI」这条架构约束，防止后续改动把常驻开销带回来。
- **修复默认规则丢失**：首次启动播种的默认规则之前只存在于内存、从未落盘，用户不改任何设置的话下次启动会全部消失。
- `build.sh` 改为 `swift build -c release` + 拷贝两个可执行文件，新增 `--no-install`（只构建不安装）。
- **本地化**：界面文案全部抽到 `Resources/{en,zh-Hans}.lproj/Localizable.strings`（50 条），代码改用语义化 key + `L10n.t(...)`；系统语言为英文时菜单栏与设置窗口完整显示英文。新增 5 个测试校验两份表 key 一致、无空翻译、代码用到的 key 都存在、无残留 key、`%@` 占位符数量一致。
- **统一日志**：`print` / `NSLog` 全部换成 `os.Logger`，按 `app / monitor / input-source / rules / settings` 分类，可用 `log stream --predicate 'subsystem == "com.qingwei.inputswitch"'` 过滤；输入法切换失败现在会记 error 级别日志。
- `handleAppChange` 收敛为「算出目标输入法 → 切一次 → 记录结果」，去掉重复调用。
- **Swift 6 语言模式**：`swift-tools-version` 升到 6.0 并启用 `swiftLanguageModes: [.v6]`。`RuleStore` / `AppMonitor` / `InputMethodManager` / 两个 delegate 标注 `@MainActor`，全局可变的图标缓存收进 `@MainActor` 类型；通知回调在 `.main` 队列上显式 `MainActor.assumeIsolated`，`Process.terminationHandler` 回主 actor 清理。`-strict-concurrency=complete` 下零警告。
- **UI 文件拆分**：`SettingsView.swift`（753 行）按职责拆成 `SettingsView` / `RuleRow` / `AddRuleSheet` / `AutoInputMenu` 四个文件。

### 发布工程（加固版，未接入真实凭据）
- **`build.sh` 支持三种签名模式**：不设置 `SIGN_IDENTITY` 时是 ad-hoc（零身份信息）；设为证书 SHA-1 时用自签名证书签名（免费，签名身份稳定）；设为 Developer ID 名称并加 `SIGN_HARDENED=1` 时用 hardened runtime + 时间戳，满足公证要求。均由内向外签名并 `codesign --verify`。
- **自签名证书方案**：新增 `scripts/make-self-signed-cert.sh`，一条命令生成代码签名证书并输出 GitHub Secret 内容；签名要求变成 `certificate leaf = H"…"`，用户升级后 TCC 授权不再重置。自签名证书无需 `sudo` 加入信任列表——CI 里用 SHA-1 指定身份即可签名。
- **发布流水线** `.github/workflows/release.yml`：按配置的 secrets 自动选择 ad-hoc / 自签名 / Developer ID 三种模式；推送 `v*` tag 时签名 →（Developer ID 时）公证 + 装订 → 打包 zip/dmg + SHA256 → 建 GitHub Release，并按模式附上对应的安装说明；手动触发只做演练并上传产物。
- **发布前自检** `scripts/release-check.sh`：检查仓库里没有凭据文件 / 私钥内容、工作区干净、二进制里没有本机路径与用户名、菜单栏进程不链接 SwiftUI、本地化资源齐全，并提示当前签名身份会公开哪些信息。
- **凭据防泄露**：`.gitignore` 覆盖 `*.p12` / `*.cer` / `*.mobileprovision` / `ExportOptions.plist` / 私钥；CI 增加守卫，即使 `git add -f` 强推也会被拦下。
- **`docs/RELEASING.md`**：一次性准备、secrets 清单、发布步骤、撤销方式，以及「签名必然公开证书姓名 / Team ID」的隐私说明与三条应对方案。

### 新增
- 中文、英文分开的双版 README（`README.md` 中文、`README_EN.md` 英文）。

### 变更
- **转为纯菜单栏后台应用**：`Info.plist` 增加 `LSUIElement=true`，移除 Dock 图标，仅保留顶部菜单栏图标；启动与关闭窗口都安静留在后台（不再自动弹窗）。

### 修复
- **输入法下拉去重与中文化**：`InputMethodManager` 过滤掉 `TISTypeKeyboardInputMethodModeEnabled` 父容器类型（如"简体中文"包裹"简体拼音"造成的重复项），并加名称去重兜底；`Info.plist` 声明 `CFBundleLocalizations`（en/zh-Hans），使输入法名称跟随系统语言显示「简体拼音」而非英文「Pinyin – Simplified」。
- **通用设置开关位置**：「启用自动切换」「开机启动」两个开关改为显示在文字左侧（开关 + 文字 的横向排列）。

### 优化（UI 精致打磨，保持液态玻璃 + 深灰美学）
- **头部状态胶囊**：主窗口右上角新增「运行中 / 已暂停」实时状态点，随「启用自动切换」开关联动。
- **通用设置前置图标**：三个设置项各自加上前导 SF 图标磁贴（`IconTile`），排版更规整；默认输入法在关闭自动切换时同步置灰。
- **规则区状态联动与计数**：关闭自动切换时显示「暂不生效」提示条并整组置灰禁点；标题旁新增规则数量徽标。
- **规则空状态引导**：从一行纯文字升级为「图标 + 说明 + 添加第一条规则」的一级引导。
- **规则行动效**：新增 / 删除带平滑过渡（插入下滑、删除缩放淡出，时长 0.2s）。
- **输入法下拉框自制化**：改用普通 Button + popover 实现的自制下拉（`AutoInputMenu`），宽度经 `.frame` 固定（不再随输入法名称长短变化）、无原生控件那种突兀的白条背景；「默认输入法」与规则行共用同一组件，样式统一，点击弹出列表并对当前项打勾。
- **删除按钮常显 + 二段式确认**：删除按钮置于输入法下拉框左侧并整体右对齐；首次点击按钮变红，悬停提示「再次点击确定删除」，再点一次才真正删除，降低误删风险，且不因悬停于下拉框而无法删除。
- **无障碍**：所有结构过渡接入 `accessibilityReduceMotion`，系统开启「减少动态效果」时自动关闭动画。
- 清理 `AddRuleSheet` 重复的 `.accentColor` 修饰。

---

## [2026-08-18] — 初始开发（单日迭代）

以下特性均于 2026-08-18 实现并验证。

### 新增
- **核心功能**：监听前台 App 切换（80ms 防抖），按规则自动切换输入法（Carbon TIS API）。
- **默认规则**：Terminal / iTerm2 / VS Code / Xcode / Warp → ABC（英文）；微信 → 拼音（简体）。
- **规则管理 UI**：新增 / 删除规则，下拉即时切换目标输入法。
- **双入口**：Dock 图标 + 菜单栏常驻图标（左键开主窗口、右键菜单）。
- **⌘W 关闭主窗口**：关闭后应用常驻菜单栏，点 Dock 可重开。
- **开机启动**：通用设置中通过 `SMAppService.mainApp` 注册登录项。
- **液态玻璃界面（macOS 26）**：窗口 `NSVisualEffectView(.hudWindow)` + 卡片 `.glassEffect()` + 规则行玻璃，旧系统回退毛玻璃。
- **深灰主题**：统一深灰强调色与 Dock 图标（深灰方块 + 白色键盘符号）。
- **隐藏系统滚动条**：让内容更轻地悬浮于玻璃窗口。
- **GPLv3 许可**与 GitHub 开源仓库（`amuwxf/AutoSwitchInput`）。

### 变更
- 输入法切换由 SwiftUI `MenuBarExtra` 改为 **NSStatusItem + main.swift** 原生方案（`MenuBarExtra` 在 swiftc 直接编译下不渲染图标）。
- 应用名由 `AutoSwitchInputMethod` 改为 **`AutoSwitchInput`**。
- 开关颜色由系统蓝改为深灰（`Toggle` 的 `.tint()` 控制开态，而非 `.accentColor()`）。
- 编译目标锁定 **arm64-apple-macosx14.0**，部署到 `/Applications`。

### 修复
- 主窗口首次打开时尺寸塌缩为 0 宽。
- 主窗口液态玻璃被渲染成透明椭圆（`.glassEffect()` 默认 capsule 形状）→ 改为 `.glassEffect(in: .rect(cornerRadius:))`。
- 关闭主窗口后再点 Dock 无法重开（旧窗口强引用残留）→ 关闭后重建干净窗口。

---

## 说明

- 本仓库无语义化版本号发布记录，变更以日期里程碑归档。
- 输入法切换依赖系统输入监控 / 辅助功能授权。
