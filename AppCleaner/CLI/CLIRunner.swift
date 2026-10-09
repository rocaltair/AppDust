import AppKit
import Foundation

enum CLIRunner {

    static var shouldRun: Bool {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else { return false }
        let flags = ["--scan", "--list-apps", "--trash", "--help", "-h"]
        return args.contains { flags.contains($0) || $0.hasSuffix(".app") }
    }

    static func run() -> Int32 {
        let args = Array(CommandLine.arguments.dropFirst())
        var json = false
        var includeSystem = true
        var listApps = false
        var scanPath: String?
        var trashPaths: [String] = []
        var customHome: String?

        var index = 0
        while index < args.count {
            switch args[index] {
            case "--json":
                json = true
            case "--no-system":
                includeSystem = false
            case "--list-apps":
                listApps = true
            case "--scan":
                index += 1
                if index < args.count { scanPath = args[index] }
            case "--trash":
                index += 1
                if index < args.count { trashPaths.append(args[index]) }
            case "--home":
                index += 1
                if index < args.count { customHome = args[index] }
            case "--help", "-h":
                printUsage()
                return 0
            default:
                if args[index].hasSuffix(".app") {
                    scanPath = args[index]
                } else if args[index].hasPrefix("/") || args[index].hasPrefix("~") || args[index].hasPrefix("./") {
                    trashPaths.append(args[index])
                }
            }
            index += 1
        }

        if !trashPaths.isEmpty {
            return trash(paths: trashPaths)
        }

        if listApps {
            return printAppList(json: json)
        }

        guard let rawPath = scanPath else {
            printUsage()
            return 2
        }

        let path = (rawPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            FileHandle.standardError.write(Data("找不到：\(url.path)\n".utf8))
            return 1
        }

        let app = AppInfo(url: url)
        let allApps = AppCatalog.installedApps(includeSystemApps: true)
        var options = ScanOptions()
        options.includeSystemLocations = includeSystem

        let started = Date()
        let home = customHome.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let outcome = AppScanner.scan(app: app, allApps: allApps, options: options, home: home, progress: nil)
        let elapsed = Date().timeIntervalSince(started)

        let totalBytes = outcome.items.reduce(Int64(0)) { $0 + $1.sizeBytes }

        if json {
            let payload: [String: Any] = [
                "app": app.url.path,
                "name": app.name,
                "bundleID": app.bundleID ?? NSNull(),
                "version": app.versionText ?? NSNull(),
                "elapsed": elapsed,
                "scannedRoots": outcome.scannedRoots,
                "totalBytes": totalBytes,
                "errors": outcome.errors,
                "items": outcome.items.map { item in
                    [
                        "path": item.url.path,
                        "kind": item.kind.rawValue,
                        "confidence": item.confidence == .high ? "high" : "medium",
                        "sizeBytes": item.sizeBytes,
                        "fileCount": item.fileCount,
                        "scope": item.scope.rawValue,
                        "requiresAdmin": item.requiresAdmin,
                        "reason": item.reason,
                    ] as [String: Any]
                },
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            return 0
        }

        print("应用：\(app.name)  \(app.bundleID ?? "-")  \(app.versionText ?? "-")")
        print("路径：\(app.url.path)")
        print("耗时：\(String(format: "%.2f", elapsed))s  扫描位置：\(outcome.scannedRoots)  项目：\(outcome.items.count)  合计：\(FileSize.human(totalBytes))")
        print(String(repeating: "-", count: 72))
        for item in outcome.items {
            let confidence = item.confidence == .high ? "确定" : "可能"
            let admin = item.requiresAdmin ? " [需管理员]" : ""
            print("[\(confidence)] \(pad(FileSize.human(item.sizeBytes), 12)) \(item.kind.title.padding(toLength: 10, withPad: " ", startingAt: 0))\(admin)")
            print("    \(item.url.path)")
            print("    理由：\(item.reason)")
        }
        if !outcome.errors.isEmpty {
            print(String(repeating: "-", count: 72))
            print("扫描告警（\(outcome.errors.count)）：")
            outcome.errors.forEach { print("  · \($0)") }
        }
        return 0
    }

    private static func trash(paths: [String]) -> Int32 {
        let items = paths
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { ScanItem.adHoc(url: $0) }

        guard !items.isEmpty else {
            FileHandle.standardError.write(Data("没有找到可处理的路径\n".utf8))
            return 1
        }

        let box = ResultBox()
        Task { @MainActor in
            let results = await RemovalService.remove(items: items, mode: .trash)
            box.results = results
            box.finished = true
        }
        let deadline = Date().addingTimeInterval(120)
        while !box.finished, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard box.finished else {
            FileHandle.standardError.write(Data("删除超时\n".utf8))
            return 1
        }

        var failed = 0
        for result in box.results {
            if !result.success { failed += 1 }
            print("\(result.success ? "成功" : "失败")\t\(result.path)\t\(result.message ?? "")")
        }
        return failed == 0 ? 0 : 1
    }

    private static func printAppList(json: Bool) -> Int32 {
        let apps = AppCatalog.installedApps(includeSystemApps: true)
        if json {
            let payload: [[String: Any]] = apps.map {
                [
                    "name": $0.name,
                    "path": $0.url.path,
                    "bundleID": $0.bundleID ?? NSNull(),
                    "version": $0.versionText ?? NSNull(),
                ]
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            return 0
        }
        for app in apps {
            print("\(app.name)\t\(app.bundleID ?? "-")\t\(app.url.path)")
        }
        FileHandle.standardError.write(Data("共 \(apps.count) 个应用\n".utf8))
        return 0
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private static func printUsage() {
        print("""
        AppCleaner \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")

        用法：
          AppCleaner --list-apps [--json]        列出已安装应用
          AppCleaner --scan /Applications/Foo.app [--json] [--no-system]
                                                 扫描某应用的关联文件
          AppCleaner --trash <路径> [<路径>…]    把路径移到废纸篓

        选项：
          --json        以 JSON 输出
          --no-system   不扫描 /Library 等系统级位置
          --home <目录> 用指定目录代替真实主目录（测试用）

        不带上述参数启动时，会打开图形界面。
        """)
    }
}

/// 在命令行模式下把异步结果搬回主线程。
final class ResultBox: @unchecked Sendable {
    var results: [RemovalResult] = []
    var finished = false
}
