import AppKit
import Foundation

/// 一个已安装的应用程序包。
struct AppInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String?
    let shortVersion: String?
    let buildVersion: String?
    let executableName: String?
    let displayName: String?
    let isSystemApp: Bool

    var id: String { url.path }

    var versionText: String? {
        guard let shortVersion, !shortVersion.isEmpty else { return nil }
        if let buildVersion, !buildVersion.isEmpty, buildVersion != shortVersion {
            return "\(shortVersion) (\(buildVersion))"
        }
        return shortVersion
    }

    init(url: URL) {
        self.url = url
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        name = url.deletingPathExtension().lastPathComponent
        let rawID = info["CFBundleIdentifier"] as? String
        bundleID = (rawID?.isEmpty == false) ? rawID : nil
        shortVersion = (info["CFBundleShortVersionString"] as? String)
        buildVersion = (info["CFBundleVersion"] as? String)
        executableName = (info["CFBundleExecutable"] as? String)
        displayName = (info["CFBundleDisplayName"] as? String)
        isSystemApp = url.path.hasPrefix("/System/")
    }
}

/// 扫描 /Applications 等目录，得到已安装应用列表。
enum AppCatalog {
    static func installedApps(includeSystemApps: Bool) -> [AppInfo] {
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        if includeSystemApps {
            roots.append(URL(fileURLWithPath: "/System/Applications"))
        }

        var result: [AppInfo] = []
        var seen = Set<String>()
        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            for appURL in findAppBundles(in: root, maxDepth: 2) {
                let info = AppInfo(url: appURL)
                if seen.insert(info.id).inserted {
                    result.append(info)
                }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func findAppBundles(in root: URL, maxDepth: Int) -> [URL] {
        var found: [URL] = []
        var queue: [(URL, Int)] = [(root, 0)]
        let fm = FileManager.default
        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            guard let children = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                if child.pathExtension == "app" {
                    found.append(child)
                    continue
                }
                guard depth + 1 <= maxDepth else { continue }
                if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    queue.append((child, depth + 1))
                }
            }
        }
        return found
    }
}
