## 安装

1. 下载 `AutoSwitchInput-*.zip` 或 `.dmg`
2. 解压后把 `AutoSwitchInput.app` 拖进 `/Applications`

## ⚠️ 首次打开需要手动放行

本版本**没有经过 Apple 公证**（发布者没有付费开发者账号），
macOS 的 Gatekeeper 会拦住它。三种放行方式任选其一：

- **右键 App → 打开** → 在弹窗里再次点「打开」
- **系统设置 → 隐私与安全性** → 页面底部「仍要打开」
- 终端执行：

  ```bash
  xattr -dr com.apple.quarantine /Applications/AutoSwitchInput.app
  ```

## 授权

首次切换应用时，按系统提示授予 **输入监控** 与 **辅助功能** 权限：

> 系统设置 → 隐私与安全性 → 输入监控 / 辅助功能 → 勾选 AutoSwitchInput

## 校验

```bash
shasum -a 256 -c SHA256SUMS.txt
```

## 介意手动放行？

clone 仓库后本地编译，本机编译不经过 Gatekeeper：

```bash
git clone https://github.com/amuwxf/AutoSwitchInput.git
cd AutoSwitchInput
bash build.sh
```

## 卸载

退出菜单栏应用后删除 `/Applications/AutoSwitchInput.app` 即可；
规则保存在 `~/Library/Preferences/com.qingwei.inputswitch.plist`。
