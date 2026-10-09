// 生成应用图标（blue→purple 圆角方块 + trash 符号），输出 AppCleaner.icns
// 用法：swift scripts/make-icon.swift <输出目录>
import AppKit
import Foundation

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outputDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

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
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.set()
    bounds.fill()

    let inset = size * 0.055
    let body = NSBezierPath(
        roundedRect: bounds.insetBy(dx: inset, dy: inset),
        xRadius: size * 0.235,
        yRadius: size * 0.235
    )
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.52, blue: 0.99, alpha: 1),
        NSColor(srgbRed: 0.38, green: 0.22, blue: 0.85, alpha: 1),
    ])!
    gradient.draw(in: body, angle: -60)

    if let symbol = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.60, weight: .bold)
        if let configured = symbol.withSymbolConfiguration(config) {
            let target = NSRect(
                x: (size - configured.size.width) / 2,
                y: (size - configured.size.height) / 2 - size * 0.01,
                width: configured.size.width,
                height: configured.size.height
            )
            let tinted = NSImage(size: configured.size, flipped: false) { rect in
                configured.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    return rep.representation(using: .png, properties: [:])
}

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

for (name, pixels) in variants {
    guard let data = renderPNG(pixels: pixels) else {
        FileHandle.standardError.write(Data("渲染 \(name) 失败\n".utf8))
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", outputDir.appendingPathComponent("AppCleaner.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil 失败\n".utf8))
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)
print("已生成 \(outputDir.appendingPathComponent("AppCleaner.icns").path)")
