import Foundation

/// 文本归一化：转小写并去掉所有非字母数字字符。
/// 用字符遍历实现，避免正则转义问题（"Visual Studio Code" -> "visualstudiocode"）。
enum TextKey {
    static func normalize(_ text: String) -> String {
        var out = ""
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

/// 一个待清理应用的身份信息：Bundle ID、各种候选名称、签名里的 App Group。
struct AppIdentity {
    let appURL: URL
    let bundleID: String?
    /// 原始候选名称（应用文件名、CFBundleName、CFBundleDisplayName、CFBundleExecutable）。
    let tokens: [String]
    /// 归一化后的候选名称（长度 >= 3）。
    let normalizedTokens: [String]
    let teamIdentifier: String?
    let appGroups: [String]
    /// 归一化后的 Bundle ID，供前缀比较使用。
    let normalizedBundleID: String?

    init(app: AppInfo) {
        appURL = app.url
        bundleID = app.bundleID
        normalizedBundleID = app.bundleID.map(TextKey.normalize)

        var candidates: [String] = [app.name]
        if let d = app.displayName { candidates.append(d) }
        if let e = app.executableName { candidates.append(e) }
        if let b = app.bundleID {
            // com.foo.Bar -> Bar，很多 Electron 应用用这个命名数据目录
            if let last = b.split(separator: ".").last, last.count >= 3 {
                candidates.append(String(last))
            }
        }
        var seen = Set<String>()
        var raw: [String] = []
        var normalized: [String] = []
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            raw.append(trimmed)
            let key = TextKey.normalize(trimmed)
            if key.count >= 3 { normalized.append(key) }
        }
        tokens = raw
        normalizedTokens = normalized

        let meta = AppMetadataReader.read(appURL: app.url)
        teamIdentifier = meta.teamIdentifier
        appGroups = meta.appGroups
    }
}

struct AppMetadata {
    var teamIdentifier: String?
    var appGroups: [String] = []
}

/// 读取签名里的 entitlements（team id / app groups），失败就返回空值。
enum AppMetadataReader {
    private static var cache: [String: AppMetadata] = [:]
    private static let lock = NSLock()

    static func read(appURL: URL) -> AppMetadata {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[appURL.path] { return cached }

        var meta = AppMetadata()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", appURL.path]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
               let plist = object as? [String: Any] {
                if let team = plist["com.apple.developer.team-identifier"] as? String {
                    meta.teamIdentifier = team
                }
                if let groups = plist["com.apple.security.application-groups"] as? [String] {
                    meta.appGroups = groups
                }
            }
        } catch {
            // 未签名 / codesign 不可用时静默降级
        }
        cache[appURL.path] = meta
        return meta
    }
}

/// 其它已安装应用的索引，用于避免“相似名称”规则误伤别的应用。
struct OtherAppIndex {
    private var identifiers: Set<String> = []
    private var nameKeys: Set<String> = []

    init(apps: [AppInfo], target: AppIdentity) {
        let targetPath = target.appURL.path
        let targetID = target.bundleID?.lowercased()
        let targetKeys = Set(target.normalizedTokens)

        for app in apps {
            if app.url.path == targetPath { continue }
            if let id = app.bundleID?.lowercased() {
                if id == targetID { continue }
                identifiers.insert(id)
            }
            var names = [app.name]
            if let d = app.displayName { names.append(d) }
            for name in names {
                let key = TextKey.normalize(name)
                if key.count >= 3, !targetKeys.contains(key) {
                    nameKeys.insert(key)
                }
            }
        }
    }

    func belongsToOtherApp(entryName: String, key: String) -> Bool {
        if identifiers.contains(entryName.lowercased()) { return true }
        if !key.isEmpty, nameKeys.contains(key) { return true }
        return false
    }
}
