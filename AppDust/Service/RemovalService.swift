import AppKit
import Foundation

enum RemovalMode {
    case trash
    case permanent
}

struct RemovalResult: Identifiable {
    let path: String
    let name: String
    let success: Bool
    let message: String?
    var id: String { path }
}

enum RemovalService {

    static func remove(items: [ScanItem], mode: RemovalMode) async -> [RemovalResult] {
        var results: [RemovalResult] = []
        let privileged = items.filter(\.requiresAdmin)
        let normal = items.filter { !$0.requiresAdmin }

        if !normal.isEmpty {
            switch mode {
            case .trash:
                results += await moveToTrash(normal)
            case .permanent:
                results += removeDirectly(normal)
            }
        }
        if !privileged.isEmpty {
            results += await removeWithAdminRights(privileged)
        }
        return results
    }

    // MARK: - 普通用户权限

    private static func moveToTrash(_ items: [ScanItem]) async -> [RemovalResult] {
        await withCheckedContinuation { continuation in
            let urls = items.map(\.url)
            NSWorkspace.shared.recycle(urls) { mapping, error in
                var results: [RemovalResult] = []
                for item in items {
                    let stillThere = FileManager.default.fileExists(atPath: item.url.path)
                    if !stillThere {
                        let trashedTo = mapping[item.url]?.path
                        results.append(RemovalResult(
                            path: item.url.path,
                            name: item.name,
                            success: true,
                            message: trashedTo.map { "已移到 \($0)" }
                        ))
                    } else {
                        results.append(RemovalResult(
                            path: item.url.path,
                            name: item.name,
                            success: false,
                            message: error?.localizedDescription ?? "无法移入废纸篓（可能没有权限）"
                        ))
                    }
                }
                continuation.resume(returning: results)
            }
        }
    }

    private static func removeDirectly(_ items: [ScanItem]) -> [RemovalResult] {
        items.map { item in
            do {
                try FileManager.default.removeItem(at: item.url)
                return RemovalResult(path: item.url.path, name: item.name, success: true, message: nil)
            } catch {
                return RemovalResult(path: item.url.path, name: item.name, success: false, message: error.localizedDescription)
            }
        }
    }

    // MARK: - 管理员权限

    /// 系统级项目（/Library 等）需要管理员权限：生成脚本后用 osascript 提权执行，
    /// 脚本输出 OK/FAIL 行用于回读实际结果。
    private static func removeWithAdminRights(_ items: [ScanItem]) async -> [RemovalResult] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let results = runPrivilegedScript(items)
                continuation.resume(returning: results)
            }
        }
    }

    private static func runPrivilegedScript(_ items: [ScanItem]) -> [RemovalResult] {
        let fm = FileManager.default
        let supportDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.rocaltair.AppDust", isDirectory: true)
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let scriptURL = supportDir.appendingPathComponent("privileged-remove-\(UUID().uuidString).sh")

        var lines = ["#!/bin/sh", "set +e"]
        for item in items {
            let path = item.url.path
            if item.kind.isLaunchItem {
                if path.hasPrefix("/Library/LaunchDaemons") {
                    lines.append("/bin/launchctl bootout system \(shellQuote(path)) >/dev/null 2>&1")
                } else if path.hasPrefix("/Library/LaunchAgents") {
                    lines.append("/bin/launchctl bootout gui/$(/usr/bin/id -u) \(shellQuote(path)) >/dev/null 2>&1")
                }
            }
            lines.append("/bin/rm -rf \(shellQuote(path))")
            lines.append("if [ -e \(shellQuote(path)) ]; then echo \"FAIL\t\(path)\"; else echo \"OK\t\(path)\"; fi")
        }
        let script = lines.joined(separator: "\n") + "\n"

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            return items.map {
                RemovalResult(path: $0.url.path, name: $0.name, success: false, message: "无法写入临时脚本：\(error.localizedDescription)")
            }
        }
        defer { try? fm.removeItem(at: scriptURL) }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }

        let appleScript = "do shell script \"/bin/sh \(appleScriptEscape(scriptURL.path)) 2>&1\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        var output = ""
        var failureText: String?
        do {
            try process.run()
            output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let errText = String(data: errData, encoding: .utf8) ?? ""
                failureText = errText.trimmingCharacters(in: .whitespacesAndNewlines)
                if failureText?.isEmpty ?? true { failureText = "管理员授权失败（退出码 \(process.terminationStatus)）" }
            }
        } catch {
            failureText = error.localizedDescription
        }

        var status: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            status[String(parts[1])] = String(parts[0])
        }

        return items.map { item in
            switch status[item.url.path] {
            case "OK":
                return RemovalResult(path: item.url.path, name: item.name, success: true, message: "已永久删除（管理员权限）")
            case "FAIL":
                return RemovalResult(path: item.url.path, name: item.name, success: false, message: "删除失败，可能仍被占用或受系统保护")
            default:
                return RemovalResult(path: item.url.path, name: item.name, success: false, message: failureText ?? "未能确认删除结果")
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
