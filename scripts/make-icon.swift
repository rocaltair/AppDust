// 把一张方图裁成 macOS 应用图标（圆角超椭圆 + 投影）并生成 .icns
// 用法：swift scripts/make-icon.swift <源图.png> <输出目录> [名字(默认 AppDust)]
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("用法：make-icon.swift <源图.png> <输出目录> [名字]\n".utf8))
    exit(2)
}

let sourceURL = URL(fileURLWithPath: args[1])
let outputDir = URL(fileURLWithPath: args[2])
let name = args.count > 3 ? args[3] : "AppDust"

guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("无法读取 \(sourceURL.path)\n".utf8))
    exit(1)
}

/// 找出非白色内容的外接矩形（归一化，原点左下）。
/// 模型常常在画布四周留一圈白边，直接贴进圆角遮罩会露出白色描边。
/// 全出血的图会得到接近整幅的矩形，等价于不裁。
func contentBounds(of image: NSImage, side: Int = 512) -> NSRect {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: side * 4,
        bitsPerPixel: 32
    ) else { return NSRect(x: 0, y: 0, width: 1, height: 1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.bitmapData else { return NSRect(x: 0, y: 0, width: 1, height: 1) }
    var minX = side, minY = side, maxX = -1, maxY = -1
    for y in 0..<side {
        let row = data + y * rep.bytesPerRow
        for x in 0..<side {
            let p = row + x * 4
            let r = Int(p[0]), g = Int(p[1]), b = Int(p[2]), a = Int(p[3])
            if a > 16, !(r > 245 && g > 245 && b > 245) {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX > minX, maxY > minY else { return NSRect(x: 0, y: 0, width: 1, height: 1) }

    let w = CGFloat(maxX - minX + 1) / CGFloat(side)
    let h = CGFloat(maxY - minY + 1) / CGFloat(side)
    let yBottom = CGFloat(side - maxY - 1) / CGFloat(side)
    return NSRect(x: CGFloat(minX) / CGFloat(side), y: yBottom, width: w, height: h)
}

let crop = contentBounds(of: source)
let sourceSize = source.size
let sourceRect = NSRect(
    x: crop.minX * sourceSize.width,
    y: crop.minY * sourceSize.height,
    width: crop.width * sourceSize.width,
    height: crop.height * sourceSize.height
)
print(String(format: "内容区域：x=%.3f y=%.3f w=%.3f h=%.3f", crop.minX, crop.minY, crop.width, crop.height))

// macOS 图标网格：1024 画布内 824 的圆角方块（四周留白 100），圆角半径 185.6
let canvasRatio: CGFloat = 1024
let contentRatio: CGFloat = 824
let cornerRatio: CGFloat = 185.6
let padding = (canvasRatio - contentRatio) / 2
let radiusRatio = cornerRatio / contentRatio

func renderPNG(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    let scale = size / canvasRatio
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.set()
    bounds.fill()

    let content = bounds.insetBy(dx: padding * scale, dy: padding * scale)
    let shape = NSBezierPath(
        roundedRect: content,
        xRadius: content.width * radiusRatio,
        yRadius: content.width * radiusRatio
    )

    // 投影：带阴影实心填充一次，之后再把图裁进同一个形状
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = size * 0.018
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor.black.set()
    shape.fill()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let shadowless = NSShadow()
    shadowless.shadowColor = .clear
    shadowless.shadowBlurRadius = 0
    shadowless.set()
    source.draw(in: content, from: sourceRect, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let iconset = outputDir.appendingPathComponent("\(name).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (file, pixels) in variants {
    guard let data = renderPNG(pixels: pixels) else {
        FileHandle.standardError.write(Data("渲染 \(file) 失败\n".utf8))
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent(file))
}

let icnsURL = outputDir.appendingPathComponent("\(name).icns")
try? FileManager.default.removeItem(at: icnsURL)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil 失败\n".utf8))
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)
print("已生成 \(icnsURL.path)")
