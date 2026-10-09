import Foundation

struct ScanOptions {
    var includeUserLocations = true
    var includeSystemLocations = true
}

struct ScanOutcome {
    var items: [ScanItem] = []
    var scannedRoots = 0
    var errors: [String] = []
}

private struct ScanRoot {
    let url: URL
    let location: ScanLocation
    let scope: Scope
    let allowFuzzy: Bool
    /// 供应商目录：一级匹配不上时，再往下一层按精确名称匹配（如 Application Support/Google/Chrome）。
    let descendOneLevel: Bool
}

final class AppScanner {

    // MARK: - 扫描入口

    static func scan(
        app: AppInfo,
        allApps: [AppInfo],
        options: ScanOptions,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        progress: ((String) -> Void)? = nil
    ) -> ScanOutcome {
        let identity = AppIdentity(app: app)
        let others = OtherAppIndex(apps: allApps, target: identity)

        var outcome = ScanOutcome()
        var itemsByPath: [String: ScanItem] = [:]
        var order: [String] = []

        func record(_ url: URL, kind: ItemKind, match: MatchInfo, scope: Scope) {
            guard itemsByPath[url.path] == nil else { return }
            let parent = url.deletingLastPathComponent()
            let writable = FileManager.default.isWritableFile(atPath: parent.path)
            itemsByPath[url.path] = ScanItem(
                url: url,
                kind: kind,
                confidence: match.confidence,
                scope: scope,
                requiresAdmin: !writable,
                reason: match.reason
            )
            order.append(url.path)
        }

        for root in rootList(home: home, options: options) {
            progress?("扫描 \(root.url.path)")
            outcome.scannedRoots += 1
            let entries = contents(of: root.url, outcome: &outcome)
            for entry in entries {
                let name = entry.lastPathComponent
                let dirKeys: Set<URLResourceKey> = [.isDirectoryKey]
                let isDir = (try? entry.resourceValues(forKeys: dirKeys).isDirectory) ?? false

                if let match = ItemMatcher.match(
                    entryName: name,
                    location: root.location,
                    identity: identity,
                    others: others,
                    allowFuzzy: root.allowFuzzy
                ) {
                    record(entry, kind: root.location.kind, match: match, scope: root.scope)
                    continue
                }

                guard root.descendOneLevel, isDir, !isSystemVendorDir(name) else { continue }
                for child in contents(of: entry, outcome: &outcome) {
                    guard let match = ItemMatcher.match(
                        entryName: child.lastPathComponent,
                        location: root.location,
                        identity: identity,
                        others: others,
                        allowFuzzy: false
                    ) else { continue }
                    record(child, kind: root.location.kind, match: match, scope: root.scope)
                }
            }
        }

        // 应用程序本体
        if app.url.path != Bundle.main.bundleURL.path {
            record(
                app.url,
                kind: .appBundle,
                match: MatchInfo(confidence: .high, reason: "应用程序本体"),
                scope: app.isSystemApp ? .system : .user
            )
        }

        // 并行统计体积
        let urls = order.compactMap { itemsByPath[$0]?.url }
        var sizes = [Int64](repeating: 0, count: urls.count)
        var counts = [Int](repeating: 0, count: urls.count)
        if !urls.isEmpty {
            sizes.withUnsafeMutableBufferPointer { sizeBuffer in
                counts.withUnsafeMutableBufferPointer { countBuffer in
                    DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                        let measured = FileSize.measure(urls[index])
                        sizeBuffer[index] = measured.bytes
                        countBuffer[index] = measured.count
                    }
                }
            }
        }

        var items: [ScanItem] = []
        for (index, path) in order.enumerated() {
            guard var item = itemsByPath[path] else { continue }
            item.sizeBytes = index < sizes.count ? sizes[index] : 0
            item.fileCount = index < counts.count ? counts[index] : 0
            items.append(item)
        }
        items.sort {
            if $0.kind.sortOrder != $1.kind.sortOrder { return $0.kind.sortOrder < $1.kind.sortOrder }
            if $0.sizeBytes != $1.sizeBytes { return $0.sizeBytes > $1.sizeBytes }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        outcome.items = items
        return outcome
    }

    // MARK: - 私有

    private static func rootList(home: URL, options: ScanOptions) -> [ScanRoot] {
        var roots: [ScanRoot] = []
        let library = home.appendingPathComponent("Library", isDirectory: true)

        if options.includeUserLocations {
            roots += [
                ScanRoot(url: library.appendingPathComponent("Containers"), location: .containers, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Group Containers"), location: .groupContainers, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Saved Application State"), location: .savedState, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Preferences"), location: .preferences, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Preferences/ByHost"), location: .preferencesByHost, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("HTTPStorages"), location: .httpStorages, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("WebKit"), location: .webKit, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Cookies"), location: .cookies, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Application Scripts"), location: .applicationScripts, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("LaunchAgents"), location: .launchAgents, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Application Support/CrashReporter"), location: .crashReports, scope: .user, allowFuzzy: true, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Application Support"), location: .applicationSupport, scope: .user, allowFuzzy: false, descendOneLevel: true),
                ScanRoot(url: library.appendingPathComponent("Caches"), location: .caches, scope: .user, allowFuzzy: true, descendOneLevel: true),
                ScanRoot(url: library.appendingPathComponent("Logs"), location: .logs, scope: .user, allowFuzzy: true, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Autosave Information"), location: .autosaveInformation, scope: .user, allowFuzzy: true, descendOneLevel: false),
                ScanRoot(url: library.appendingPathComponent("Internet Plug-Ins"), location: .internetPlugIns, scope: .user, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: URL(fileURLWithPath: "/Users/Shared"), location: .sharedSupport, scope: .user, allowFuzzy: false, descendOneLevel: false),
            ]
        }

        if options.includeSystemLocations {
            roots += [
                ScanRoot(url: URL(fileURLWithPath: "/Library/LaunchDaemons"), location: .launchDaemons, scope: .system, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: URL(fileURLWithPath: "/Library/LaunchAgents"), location: .launchAgents, scope: .system, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), location: .privilegedHelperTools, scope: .system, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: URL(fileURLWithPath: "/Library/Application Support"), location: .applicationSupport, scope: .system, allowFuzzy: false, descendOneLevel: true),
                ScanRoot(url: URL(fileURLWithPath: "/Library/Caches"), location: .caches, scope: .system, allowFuzzy: true, descendOneLevel: true),
                ScanRoot(url: URL(fileURLWithPath: "/Library/Preferences"), location: .preferences, scope: .system, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: URL(fileURLWithPath: "/Library/Preferences/ByHost"), location: .preferencesByHost, scope: .system, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: URL(fileURLWithPath: "/Library/Logs"), location: .logs, scope: .system, allowFuzzy: true, descendOneLevel: false),
                ScanRoot(url: URL(fileURLWithPath: "/Library/Internet Plug-Ins"), location: .internetPlugIns, scope: .system, allowFuzzy: false, descendOneLevel: false),
                ScanRoot(url: URL(fileURLWithPath: "/private/var/db/receipts"), location: .receipts, scope: .system, allowFuzzy: false, descendOneLevel: false),
            ]
        }
        return roots
    }

    private static func contents(of directory: URL, outcome: inout ScanOutcome) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            if outcome.errors.count < 20 {
                outcome.errors.append("\(directory.path): \(error.localizedDescription)")
            }
            return []
        }
    }

    private static func isSystemVendorDir(_ name: String) -> Bool {
        name.lowercased().hasPrefix("com.apple.")
    }
}
