import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppDustModel: ObservableObject {

    @Published var apps: [AppInfo] = []
    @Published var selectedAppPath: String?
    @Published var items: [ScanItem] = []
    @Published var isScanning = false
    @Published var isRemoving = false
    @Published var statusText = ""
    @Published var searchText = ""
    @Published var includeSystemApps = false
    @Published var includeSystemLocations = true
    @Published var scanErrors: [String] = []
    @Published var report: [RemovalResult] = []
    @Published var showReport = false

    var selectedApp: AppInfo? {
        guard let selectedAppPath else { return nil }
        return apps.first { $0.url.path == selectedAppPath }
    }

    var filteredApps: [AppInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedItems: [ScanItem] { items.filter(\.isSelected) }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var adminCount: Int { selectedItems.filter(\.requiresAdmin).count }
    var includesAppBundle: Bool { selectedItems.contains { $0.kind == .appBundle } }

    // MARK: - 应用列表

    func reloadApps() {
        let ownBundleID = Bundle.main.bundleIdentifier?.lowercased()
        let ownPath = Bundle.main.bundleURL.path
        apps = AppCatalog.installedApps(includeSystemApps: includeSystemApps)
            .filter { $0.url.path != ownPath && $0.bundleID?.lowercased() != ownBundleID }
        if let path = selectedAppPath, !apps.contains(where: { $0.url.path == path }) {
            selectedAppPath = nil
            items = []
        }
        statusText = "已载入 \(apps.count) 个应用"
    }

    func adoptExternalApp(at url: URL) {
        let standardized = url.standardizedFileURL
        guard standardized.pathExtension == "app" else {
            statusText = "请拖入 .app 应用程序包"
            return
        }
        if let existing = apps.first(where: { $0.url.standardizedFileURL.path == standardized.path }) {
            selectedAppPath = existing.id
        } else {
            let info = AppInfo(url: standardized)
            apps.insert(info, at: 0)
            apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            selectedAppPath = info.id
        }
        if selectedAppPath == standardized.path, items.isEmpty, !isScanning {
            Task { await scan() }
        }
    }

    // MARK: - 扫描

    func scan() async {
        guard let app = selectedApp else { return }
        isScanning = true
        statusText = "正在扫描 \(app.name) 的残留文件…"
        let allApps = apps
        var options = ScanOptions()
        options.includeSystemLocations = includeSystemLocations

        let outcome = await Task.detached(priority: .userInitiated) {
            AppScanner.scan(app: app, allApps: allApps, options: options, progress: nil)
        }.value

        items = outcome.items
        scanErrors = outcome.errors
        isScanning = false
        statusText = outcome.items.isEmpty
            ? "没有找到残留文件"
            : "共找到 \(outcome.items.count) 项，合计 \(FileSize.human(totalBytes))"
    }

    // MARK: - 选择

    func setSelected(_ id: String, to value: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isSelected = value
    }

    func selectAll(_ value: Bool) {
        for index in items.indices { items[index].isSelected = value }
    }

    func invertSelection() {
        for index in items.indices { items[index].isSelected.toggle() }
    }

    // MARK: - 删除

    func quitRunningApp() {
        guard let app = selectedApp, let bundleID = app.bundleID else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        running.forEach { $0.terminate() }
        statusText = running.isEmpty ? "该应用未在运行" : "已请求退出 \(app.name)"
    }

    func removeSelected(permanent: Bool) async {
        let targets = selectedItems
        guard !targets.isEmpty else { return }
        isRemoving = true
        statusText = permanent ? "正在删除…" : "正在移入废纸篓…"

        // 删除前尽量退出目标应用，避免文件被占用
        if let bundleID = selectedApp?.bundleID {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if !running.isEmpty {
                running.forEach { $0.terminate() }
                if targets.contains(where: { $0.kind == .appBundle }) {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                }
            }
        }

        let results = await RemovalService.remove(items: targets, mode: permanent ? .permanent : .trash)
        report = results
        showReport = true
        isRemoving = false

        let failed = results.filter { !$0.success }.count
        statusText = failed == 0
            ? "已处理 \(results.count) 项"
            : "已处理 \(results.count - failed) 项，\(failed) 项失败"

        if targets.contains(where: { $0.kind == .appBundle }), results.first(where: { $0.path == selectedAppPath })?.success == true {
            reloadApps()
            selectedAppPath = nil
            items = []
        } else {
            await scan()
        }
    }
}
