# 更新日志

本项目所有值得注意的变更均记录于此。

本文件格式遵循 [Keep a Changelog](https://keepachangelog.com/)，项目以 GPLv3 开源。

---

## [未发布 / Unreleased]

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
