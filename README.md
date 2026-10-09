# AppDust

macOS 应用数据清理工具：选中（或拖入）一个 `.app`，列出它在系统里留下的全部关联文件，勾选后一次性删除。
用 Swift + SwiftUI 写，未沙盒化，纯本地运行，不需要网络。

## 功能

- **应用列表**：扫描 `/Applications`、`~/Applications`（可选 `/System/Applications`），支持按名称或 Bundle ID 搜索。
- **拖放支持**：把任意 `.app` 拖进窗口即可扫描，无需先出现在列表里。
- **关联文件扫描**，覆盖以下位置（每项都标注匹配理由）：

  | 位置 | 说明 |
  |---|---|
  | `~/Library/Containers` | 沙盒容器（聊天记录、登录状态在这里） |
  | `~/Library/Group Containers` | 群组容器，按 Bundle ID 与签名里声明的 App Group 匹配 |
  | `~/Library/Application Support` | 支持文件，含「供应商目录/应用名」两级匹配 |
  | `~/Library/Caches`、`/Library/Caches` | 缓存 |
  | `~/Library/Preferences`、`ByHost` | 偏好设置 plist |
  | `~/Library/Saved Application State` | 窗口状态 |
  | `~/Library/Logs`、`Application Support/CrashReporter` | 日志与崩溃报告 |
  | `~/Library/HTTPStorages`、`WebKit`、`Cookies`、`Application Scripts` | 网络与脚本数据 |
  | `~/Library/LaunchAgents`、`/Library/Launch{Agents,Daemons}` | 启动项（删除前先 `launchctl bootout`） |
  | `/Library/PrivilegedHelperTools`、`/private/var/db/receipts` | 辅助工具与 pkg 安装收据 |

- **匹配规则**：Bundle ID 精确/前缀匹配为「确定」；名称归一化后相等为「确定」；名称包含应用名片段为「可能」。
  会读取签名里的 Team ID 与 App Groups，并建立「其它已安装应用」索引，避免把别人的目录当成自己的。
  永远跳过 `com.apple.*`（除非目标本身就是 Apple 应用）。
- **删除方式**：默认**移到废纸篓**（可恢复）；也可选永久删除。系统级位置（`/Library/…`）需要管理员授权，会弹出系统认证窗口。
- **删除前**会自动尝试退出正在运行的目标应用，并给出完成报告（成功/失败逐条列出）。

## 构建

```bash
./install.sh          # 构建 Release 并安装到 /Applications，然后启动
./install.sh build    # 只构建，产物在 build/DerivedData/Build/Products/Release
```

依赖 `xcodegen`（`brew install xcodegen`）与 Xcode。`project.yml` 是唯一事实来源，`AppDust.xcodeproj` 是生成物（已 gitignore）。

图标由本地 mimg（MLX）出图，再按 macOS 图标网格裁成圆角方块：

```bash
~/bin/mimg -m flux2-klein-4b-4bit -S 1024x1024 -s 4 -o /tmp/icon.png "flat vector app icon ... full bleed gradient ... no text"
swift scripts/make-icon.swift /tmp/icon.png AppDust/Resources AppDust
```

`scripts/make-icon.swift` 会自动裁掉四周白边、套 824/1024 的圆角遮罩加投影，输出多尺寸 `.icns`。
原始出图放在 `assets/AppDust-icon-source.png`。

## 命令行

同一个二进制带参数启动时不进 GUI，直接跑扫描（便于批量检查，也是本项目的验证入口）：

```bash
APP=/Applications/AppDust.app/Contents/MacOS/AppDust

$APP --list-apps [--json]                      # 列出已安装应用
$APP --scan /Applications/Foo.app [--json] [--no-system]
$APP --trash <路径> [<路径>…]                  # 把路径移到废纸篓
$APP --scan <app> --home <假主目录>            # 用指定目录代替 ~ 做隔离测试
```

`--json` 输出包含每一项的 `path / kind / confidence / sizeBytes / fileCount / requiresAdmin / reason`。

## 权限说明

- 未沙盒化，读写自己的 `~/Library` 不需要授权。
- 部分系统保护目录（通讯录、通话记录、CloudDocs 等）会被 TCC 拒绝，界面右上角会显示「N 处无法访问」，跳过即可，不影响清理。
- 删除 `/Applications` 下的应用或 `/Library` 下的数据：前者受「App 管理」保护、后者需要管理员密码，均按系统提示操作。
- 如果希望扫描/删除更彻底（例如其它用户的容器），可在「系统设置 → 隐私与安全性」里给 AppDust 授予「完全磁盘访问权限」。
