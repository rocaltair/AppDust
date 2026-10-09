import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DetailView: View {
    @EnvironmentObject private var model: AppDustModel
    @Binding var pendingTrash: Bool
    @Binding var pendingPermanent: Bool
    @State private var showErrors = false

    var body: some View {
        if let app = model.selectedApp {
            VStack(spacing: 0) {
                header(app)
                Divider()
                if model.isScanning && model.items.isEmpty {
                    scanningPlaceholder
                } else if model.items.isEmpty {
                    emptyResult
                } else {
                    itemList
                }
                Divider()
                footer(app)
            }
        } else {
            DropPlaceholder()
        }
    }

    // MARK: - 头部

    private func header(_ app: AppInfo) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: IconCache.icon(for: app, size: 48))
                .resizable()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(app.name).font(.title2.bold())
                    if let version = app.versionText {
                        Text(version).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text(app.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let bundleID = app.bundleID {
                    Text(bundleID).font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if model.isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("扫描中…").font(.callout).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Button("重新扫描") { Task { await model.scan() } }
                        .disabled(model.isScanning)
                    Button("退出应用") { model.quitRunningApp() }
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([app.url])
                    }
                }
                HStack(spacing: 8) {
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.scanErrors.isEmpty {
                        Button("\(model.scanErrors.count) 处无法访问") { showErrors.toggle() }
                            .buttonStyle(.link)
                            .font(.caption)
                            .popover(isPresented: $showErrors) {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("以下位置没有读取权限，已跳过（通常是系统 TCC 保护目录，不影响清理）")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        ForEach(model.scanErrors, id: \.self) { error in
                                            Text(error)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .padding(12)
                                    .frame(width: 420, alignment: .leading)
                                }
                                .frame(maxHeight: 320)
                            }
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - 列表

    private var itemList: some View {
        List {
            ForEach(model.items) { item in
                ItemRow(item: item, isOn: binding(for: item))
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func binding(for item: ScanItem) -> Binding<Bool> {
        Binding(
            get: { model.items.first(where: { $0.id == item.id })?.isSelected ?? false },
            set: { model.setSelected(item.id, to: $0) }
        )
    }

    private var scanningPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在扫描 \(model.selectedApp?.name ?? "") 的关联文件…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResult: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("没有找到可以清理的关联文件")
                .font(.headline)
            Text("可以在左侧重新勾选「扫描 /Library 系统级位置」，或换一个应用试试。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部操作栏

    private func footer(_ app: AppInfo) -> some View {
        VStack(spacing: 0) {
            if model.adminCount > 0 || model.includesAppBundle {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warningText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))
                Divider()
            }

            HStack(spacing: 10) {
                Button("全选") { model.selectAll(true) }
                Button("全不选") { model.selectAll(false) }
                Button("反选") { model.invertSelection() }
                Divider().frame(height: 16)

                Text("已选 \(model.selectedItems.count)/\(model.items.count) 项 · \(FileSize.human(model.selectedBytes))（共 \(FileSize.human(model.totalBytes))）")
                    .font(.callout)
                    .monospacedDigit()

                Spacer()

                if model.isRemoving {
                    ProgressView().controlSize(.small)
                }

                Button("移到废纸篓") { pendingTrash = true }
                    .disabled(model.selectedItems.isEmpty || model.isRemoving)
                Button("永久删除…") { pendingPermanent = true }
                    .disabled(model.selectedItems.isEmpty || model.isRemoving)
                    .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var warningText: String {
        var parts: [String] = []
        if model.includesAppBundle { parts.append("包含「\(model.selectedApp?.name ?? "")」应用程序本体") }
        if model.adminCount > 0 { parts.append("\(model.adminCount) 项为系统级位置，删除时需输入管理员密码") }
        return parts.joined(separator: "，") + "。"
    }
}

/// 未选择应用时的拖放入口。
struct DropPlaceholder: View {
    @EnvironmentObject private var model: AppDustModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.slash")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)

            Text("把 .app 拖到这里，或在左侧选择应用")
                .font(.title3)

            Text("AppDust 会扫描容器、缓存、偏好设置、日志、启动项等关联文件，勾选后一并清理。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Button("选择应用程序…") { openPanel() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.prompt = "选择"
        panel.message = "选择要清理的应用程序"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            model.adoptExternalApp(at: url)
        }
    }
}
