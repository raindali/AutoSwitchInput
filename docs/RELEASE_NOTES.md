## 安装

1. 下载 `AutoSwitchInput-*.zip` 或 `.dmg`
2. 解压后把 `AutoSwitchInput.app` 拖进 `/Applications`
3. 双击打开（首次会提示「已从互联网下载」，确认即可）

首次切换应用时，按系统提示授予 **输入监控** 与 **辅助功能** 权限：

> 系统设置 → 隐私与安全性 → 输入监控 / 辅助功能 → 勾选 AutoSwitchInput

## 校验

```bash
shasum -a 256 -c SHA256SUMS.txt
```

## 卸载

退出菜单栏应用后删除 `/Applications/AutoSwitchInput.app` 即可；
规则保存在 `~/Library/Preferences/com.qingwei.inputswitch.plist`。
