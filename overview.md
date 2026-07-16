# KillPort — macOS 菜单栏端口管理工具

## 交付概览

KillPort 是一个 macOS 菜单栏常驻工具，用户点击菜单栏图标弹出面板，输入端口号查询占用进程信息，并可一键终止占用进程。

- **交付状态**: 已完成
- **测试通过率**: 24/24 (100%)
- **已知问题**: 0
- **Git commits**: 2 (初始实现 + QA 测试)

## 技术栈

| 项目 | 选择 |
|------|------|
| 语言 | Swift 6.3.3 |
| UI 框架 | SwiftUI + AppKit |
| 构建 | Swift Package Manager (SPM) |
| 版本管理 | Git (本地) |
| 平台 | macOS 12+ (当前 macOS 26.5.2) |

## 文件清单

| 文件 | 说明 |
|------|------|
| `Package.swift` | SPM 包定义 |
| `Sources/KillPort/KillPortApp.swift` | @main 入口, AppDelegate |
| `Sources/KillPort/StatusBarController.swift` | 菜单栏图标 + Popover 管理 |
| `Sources/KillPort/PortScanner.swift` | lsof 封装, 端口查询 |
| `Sources/KillPort/ProcessKiller.swift` | 进程终止 (SIGTERM→SIGKILL→提权) |
| `Sources/KillPort/ContentView.swift` | SwiftUI 主视图 |
| `Sources/KillPort/Models.swift` | 数据模型 |
| `Resources/Info.plist` | App 配置 (LSUIElement=true) |
| `Scripts/build.sh` | 构建脚本 (编译+打包+签名) |
| `Tests/KillPortTests/main.swift` | 24 个 QA 测试用例 |
| `.gitignore` | Git 忽略规则 |
| `README.md` | 项目文档 |

## 使用方式

### 构建
```bash
./Scripts/build.sh
```

###运行
```bash
open KillPort.app
# 或直接双击 KillPort.app
```

### 运行测试
```bash
swiftc Sources/KillPort/Models.swift Sources/KillPort/PortScanner.swift Sources/KillPort/ProcessKiller.swift Tests/KillPortTests/main.swift -o /tmp/KillPortTests -framework AppKit -framework SwiftUI -parse-as-library && /tmp/KillPortTests
```
