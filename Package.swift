// swift-tools-version: 5.9
import PackageDescription

// 模块划分：
//   AutoSwitchInputCore    —— 规则存储 / 输入源 / 前台应用监听（不依赖 SwiftUI）
//   AutoSwitchInputUI      —— SwiftUI 设置界面
//   AutoSwitchInput        —— 菜单栏常驻进程（只依赖 Core）
//   AutoSwitchInputSettings—— 设置窗口进程（依赖 Core + UI，关窗即退出）
//
// 这样常驻进程在链接期就完全不引入 SwiftUI，也便于给 Core 写单元测试。
let package = Package(
    name: "AutoSwitchInput",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AutoSwitchInput", targets: ["AutoSwitchInput"]),
        .executable(name: "AutoSwitchInputSettings", targets: ["AutoSwitchInputSettings"]),
        .library(name: "AutoSwitchInputCore", targets: ["AutoSwitchInputCore"]),
    ],
    targets: [
        .target(name: "AutoSwitchInputCore"),
        .target(name: "AutoSwitchInputUI", dependencies: ["AutoSwitchInputCore"]),
        .executableTarget(name: "AutoSwitchInput", dependencies: ["AutoSwitchInputCore"]),
        .executableTarget(
            name: "AutoSwitchInputSettings",
            dependencies: ["AutoSwitchInputCore", "AutoSwitchInputUI"]
        ),
        .testTarget(name: "AutoSwitchInputCoreTests", dependencies: ["AutoSwitchInputCore"]),
    ]
)
