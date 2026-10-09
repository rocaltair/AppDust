import AppKit
import SwiftUI

/// 应用图标缓存，避免每次刷新都向 Workspace 请求。
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for app: AppInfo, size: CGFloat = 32) -> NSImage {
        if let cached = cache[app.url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        image.size = NSSize(width: size, height: size)
        cache[app.url.path] = image
        return image
    }
}

struct AppRow: View {
    let app: AppInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.icon(for: app))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .lineLimit(1)
                    if app.isSystemApp {
                        Text("系统")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(app.bundleID ?? app.url.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}
