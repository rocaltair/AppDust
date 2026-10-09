import Foundation

enum FileSize {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func human(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0" }
        return formatter.string(fromByteCount: bytes)
    }

    private static let measureKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isDirectoryKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
    ]

    /// 递归统计占用空间与文件数量（跳过符号链接）。
    static func measure(_ url: URL) -> (bytes: Int64, count: Int) {
        let fm = FileManager.default
        guard let values = try? url.resourceValues(forKeys: measureKeys) else { return (0, 0) }

        if values.isSymbolicLink == true { return (0, 0) }

        if values.isDirectory != true {
            return (allocated(values), 1)
        }

        var bytes: Int64 = 0
        var count = 0
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(measureKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return (0, 0) }

        for case let child as URL in enumerator {
            guard let v = try? child.resourceValues(forKeys: measureKeys) else { continue }
            if v.isSymbolicLink == true { continue }
            guard v.isRegularFile == true else { continue }
            bytes += allocated(v)
            count += 1
        }
        return (bytes, count)
    }

    private static func allocated(_ values: URLResourceValues) -> Int64 {
        if let total = values.totalFileAllocatedSize { return Int64(total) }
        if let alloc = values.fileAllocatedSize { return Int64(alloc) }
        if let size = values.fileSize { return Int64(size) }
        return 0
    }
}
