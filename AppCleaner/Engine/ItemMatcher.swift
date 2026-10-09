import Foundation

/// 一个被扫描的目录位置（决定匹配规则与项目分类）。
enum ScanLocation {
    case applicationSupport
    case caches
    case preferences
    case preferencesByHost
    case logs
    case savedState
    case containers
    case groupContainers
    case httpStorages
    case webKit
    case cookies
    case applicationScripts
    case launchAgents
    case launchDaemons
    case internetPlugIns
    case privilegedHelperTools
    case receipts
    case autosaveInformation
    case crashReports
    case sharedSupport

    var kind: ItemKind {
        switch self {
        case .applicationSupport: return .applicationSupport
        case .caches: return .caches
        case .preferences, .preferencesByHost: return .preferences
        case .logs: return .logs
        case .savedState: return .savedState
        case .containers: return .containers
        case .groupContainers: return .groupContainers
        case .httpStorages: return .httpStorages
        case .webKit: return .webKit
        case .cookies: return .cookies
        case .applicationScripts: return .applicationScripts
        case .launchAgents, .launchDaemons: return .launchItem
        case .internetPlugIns: return .plugin
        case .privilegedHelperTools: return .helperTool
        case .receipts: return .receipt
        case .autosaveInformation: return .autosave
        case .crashReports: return .crash
        case .sharedSupport: return .other
        }
    }
}

extension ItemKind {
    /// 是否需要“先 bootout 再删除”的启动项处理。
    var isLaunchItem: Bool { self == .launchItem }
}

struct MatchInfo {
    let confidence: MatchConfidence
    let reason: String
}

enum ItemMatcher {
    /// 判断某个目录条目是否属于目标应用。
    /// - Parameter allowFuzzy: 是否允许“名称包含”这类模糊匹配（供应商目录一级不做模糊匹配）。
    static func match(
        entryName: String,
        location: ScanLocation,
        identity: AppIdentity,
        others: OtherAppIndex,
        allowFuzzy: Bool
    ) -> MatchInfo? {
        let lower = entryName.lowercased()
        let key = TextKey.normalize(entryName)
        guard !key.isEmpty else { return nil }

        // 永不触碰系统自带数据，除非目标本身就是 Apple 应用
        let targetIsApple = (identity.bundleID ?? "").lowercased().hasPrefix("com.apple.")
        if !targetIsApple, lower.hasPrefix("com.apple.") { return nil }
        // 永不触碰自己
        if lower.hasPrefix("com.rocaltair.appcleaner") { return nil }

        if let bid = identity.bundleID?.lowercased(), !bid.isEmpty {
            if lower == bid {
                return MatchInfo(confidence: .high, reason: "名称与应用的 Bundle ID 相同")
            }
            if lower.hasPrefix(bid + ".") {
                if location == .savedState, lower == bid + ".savedstate" {
                    return MatchInfo(confidence: .high, reason: "保存的窗口状态")
                }
                if location == .cookies, lower == bid + ".binarycookies" {
                    return MatchInfo(confidence: .high, reason: "Cookies 文件")
                }
                if location == .preferences || location == .preferencesByHost, lower.hasSuffix(".plist") {
                    return MatchInfo(confidence: .high, reason: "应用偏好设置")
                }
                return MatchInfo(confidence: .high, reason: "名称以应用的 Bundle ID 开头")
            }
            if lower.contains(bid) {
                if location == .groupContainers || location == .receipts || bid.count >= 8 {
                    let reason = location == .receipts
                        ? "pkg 安装收据"
                        : (location == .groupContainers ? "群组容器名称包含 Bundle ID" : "名称包含应用的 Bundle ID")
                    return MatchInfo(confidence: .high, reason: reason)
                }
            }
            // 偏好设置里的 XXX.plist（以 Bundle ID 结尾段命名的情况）
            let stem = TextKey.normalize((entryName as NSString).deletingPathExtension)
            if location == .preferences || location == .preferencesByHost, stem == bid {
                return MatchInfo(confidence: .high, reason: "应用偏好设置")
            }
        }

        // 签名里声明的 App Group
        if location == .groupContainers {
            for group in identity.appGroups {
                let g = group.lowercased()
                if lower == g || lower.hasSuffix("." + g) {
                    return MatchInfo(confidence: .high, reason: "应用声明的 App Group")
                }
            }
        }

        // 名称完全相同
        if identity.normalizedTokens.contains(key) {
            return MatchInfo(confidence: .high, reason: "名称与应用名称相同")
        }

        // 去掉扩展名后的名称完全相同（例如 Foo.plist）
        let stemKey = TextKey.normalize((entryName as NSString).deletingPathExtension)
        if !stemKey.isEmpty, stemKey != key, identity.normalizedTokens.contains(stemKey) {
            return MatchInfo(confidence: .medium, reason: "去掉扩展名后与应用名称相同")
        }

        guard allowFuzzy else { return nil }
        guard !others.belongsToOtherApp(entryName: entryName, key: key) else { return nil }

        for token in identity.normalizedTokens.sorted(by: { $0.count > $1.count }) where token.count >= 5 {
            if key.hasPrefix(token) || key.contains(token) {
                return MatchInfo(confidence: .medium, reason: "名称包含应用名称片段 “\(token)”")
            }
        }
        return nil
    }
}
