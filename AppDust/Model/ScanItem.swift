import Foundation

/// 项目所在范围：用户级（~/Library 等）或系统级（/Library、/private/var/db 等）。
enum Scope: String {
    case user
    case system
}

enum MatchConfidence: Int {
    case medium = 1
    case high = 2

    var title: String {
        switch self {
        case .high: return "确定"
        case .medium: return "可能"
        }
    }
}

enum ItemKind: String, CaseIterable {
    case appBundle
    case containers
    case groupContainers
    case applicationSupport
    case caches
    case preferences
    case httpStorages
    case webKit
    case cookies
    case savedState
    case logs
    case crash
    case autosave
    case applicationScripts
    case launchItem
    case plugin
    case helperTool
    case receipt
    case other

    var title: String {
        switch self {
        case .appBundle: return "应用程序"
        case .containers: return "沙盒容器"
        case .groupContainers: return "群组容器"
        case .applicationSupport: return "支持文件"
        case .caches: return "缓存"
        case .preferences: return "偏好设置"
        case .httpStorages: return "网络存储"
        case .webKit: return "WebKit 数据"
        case .cookies: return "Cookies"
        case .savedState: return "窗口状态"
        case .logs: return "日志"
        case .crash: return "崩溃报告"
        case .autosave: return "自动保存"
        case .applicationScripts: return "应用脚本"
        case .launchItem: return "启动项"
        case .plugin: return "插件"
        case .helperTool: return "辅助工具"
        case .receipt: return "安装收据"
        case .other: return "其他"
        }
    }

    var symbol: String {
        switch self {
        case .appBundle: return "app.dashed"
        case .containers: return "shippingbox"
        case .groupContainers: return "shippingbox.fill"
        case .applicationSupport: return "folder"
        case .caches: return "internaldrive"
        case .preferences: return "slider.horizontal.3"
        case .httpStorages: return "network"
        case .webKit: return "globe"
        case .cookies: return "birthday.cake"
        case .savedState: return "macwindow"
        case .logs: return "doc.text.magnifyingglass"
        case .crash: return "exclamationmark.triangle"
        case .autosave: return "clock.arrow.circlepath"
        case .applicationScripts: return "applescript"
        case .launchItem: return "bolt.badge.clock"
        case .plugin: return "puzzlepiece.extension"
        case .helperTool: return "gearshape.2"
        case .receipt: return "doc.plaintext"
        case .other: return "questionmark.folder"
        }
    }

    var sortOrder: Int {
        switch self {
        case .appBundle: return 0
        case .containers: return 1
        case .groupContainers: return 2
        case .applicationSupport: return 3
        case .caches: return 4
        case .preferences: return 5
        case .httpStorages: return 6
        case .webKit: return 7
        case .cookies: return 8
        case .savedState: return 9
        case .logs: return 10
        case .crash: return 11
        case .autosave: return 12
        case .applicationScripts: return 13
        case .launchItem: return 14
        case .plugin: return 15
        case .helperTool: return 16
        case .receipt: return 17
        case .other: return 18
        }
    }
}

extension ScanItem {
    /// 命令行直接指定路径时构造的项目。
    static func adHoc(url: URL) -> ScanItem {
        let writable = FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
        return ScanItem(
            url: url,
            kind: .other,
            confidence: .high,
            scope: .user,
            requiresAdmin: !writable,
            reason: "命令行指定"
        )
    }
}

/// 扫描到的一条残留项目。
struct ScanItem: Identifiable, Hashable {
    let url: URL
    let kind: ItemKind
    let confidence: MatchConfidence
    let scope: Scope
    /// 删除该项目的父目录不可写，需要管理员权限。
    let requiresAdmin: Bool
    /// 匹配理由，界面上作为提示展示。
    let reason: String
    var sizeBytes: Int64 = 0
    var fileCount: Int = 0
    var isSelected: Bool = true

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var parentPath: String { url.deletingLastPathComponent().path }

    static func == (lhs: ScanItem, rhs: ScanItem) -> Bool { lhs.url.path == rhs.url.path }
    func hash(into hasher: inout Hasher) { hasher.combine(url.path) }
}
