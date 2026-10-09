import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppCleanerModel
    @State private var pendingTrash = false
    @State private var pendingPermanent = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView(pendingTrash: $pendingTrash, pendingPermanent: $pendingPermanent)
        }
        .frame(minWidth: 980, minHeight: 620)
        .onAppear { if model.apps.isEmpty { model.reloadApps() } }
        .onChange(of: model.selectedAppPath) { _, newValue in
            guard newValue != nil else { return }
            Task { await model.scan() }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert("移到废纸篓？", isPresented: $pendingTrash) {
            Button("取消", role: .cancel) { }
            Button("移到废纸篓") { Task { await model.removeSelected(permanent: false) } }
        } message: {
            Text(confirmMessage(permanent: false))
        }
        .alert("永久删除？此操作不可撤销", isPresented: $pendingPermanent) {
            Button("取消", role: .cancel) { }
            Button("永久删除", role: .destructive) { Task { await model.removeSelected(permanent: true) } }
        } message: {
            Text(confirmMessage(permanent: true))
        }
        .sheet(isPresented: $model.showReport) {
            RemovalReportView(results: model.report, isPresented: $model.showReport)
        }
    }

    private func confirmMessage(permanent: Bool) -> String {
        let count = model.selectedItems.count
        let size = FileSize.human(model.selectedBytes)
        var lines = ["将处理 \(count) 项，共 \(size)。"]
        if permanent {
            lines.append("这些项目会被直接删除，无法从废纸篓恢复。")
        } else {
            lines.append("这些项目会被移到废纸篓，之后仍可恢复。")
        }
        if model.adminCount > 0 {
            lines.append("其中 \(model.adminCount) 项位于系统级位置，需要输入管理员密码，且是永久删除。")
        }
        let hasContainers = model.selectedItems.contains { $0.kind == .containers || $0.kind == .groupContainers }
        if hasContainers {
            lines.append("沙盒容器里通常保存着聊天记录、登录状态和账号数据，删除后相当于让应用回到全新状态。")
        }
        if model.includesAppBundle {
            lines.append("包含应用程序本体「\(model.selectedApp?.name ?? "")」。")
        }
        if let app = model.selectedApp, app.bundleID != nil {
            lines.append("若该应用正在运行，会先尝试退出它。")
        }
        return lines.joined(separator: "\n")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = object as? URL else { return }
            Task { @MainActor in
                model.adoptExternalApp(at: url)
            }
        }
        return true
    }
}
