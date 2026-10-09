import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppCleanerModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedAppPath) {
                Section {
                    ForEach(model.filteredApps) { app in
                        AppRow(app: app)
                            .tag(app.url.path)
                            .contextMenu {
                                Button("在 Finder 中显示") {
                                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                                }
                            }
                    }
                } header: {
                    Text("已安装的应用（\(model.filteredApps.count)）")
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $model.searchText, placement: .sidebar, prompt: "搜索应用名称或 Bundle ID")

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("显示系统应用", isOn: $model.includeSystemApps)
                    .onChange(of: model.includeSystemApps) { _, _ in model.reloadApps() }
                Toggle("扫描 /Library 系统级位置", isOn: $model.includeSystemLocations)
                    .onChange(of: model.includeSystemLocations) { _, _ in
                        Task { await model.scan() }
                    }
                Button("重新载入应用列表") { model.reloadApps() }
                    .controlSize(.small)
            }
            .toggleStyle(.checkbox)
            .font(.callout)
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
    }
}
