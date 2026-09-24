// 生成 AppIcon 资源：蓝色渐变圆角底板 + 白色 SF Symbol（与状态栏图标同款 arrow.up.doc.on.clipboard）。
// 每个尺寸单独按像素绘制（NSBitmapImageRep，1pt = 1px），不依赖 Retina 缩放，小尺寸也清晰。
// 用法（项目根目录下）：swift scripts/gen_app_icon.swift [输出 xcassets 目录，默认 GaplessPaste/Assets.xcassets]
// 产物入库；改图标后重新跑本脚本再 make build。
import AppKit

let symbolName = "arrow.up.doc.on.clipboard"
let canvas: CGFloat = 1024
// macOS 图标网格：1024 画布内 824×824 底板，四周留白给投影
let plateRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let plateRadius: CGFloat = 185
let topColor = NSColor(srgbRed: 0.33, green: 0.64, blue: 1.00, alpha: 1)
let bottomColor = NSColor(srgbRed: 0.10, green: 0.36, blue: 0.86, alpha: 1)

struct IconSlot {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png" }
}

let slots = [16, 32, 128, 256, 512].flatMap { [IconSlot(points: $0, scale: 1), IconSlot(points: $0, scale: 2)] }

func drawIcon() {
    // 底板 + 投影
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: plateRadius, yRadius: plateRadius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    bottomColor.setFill()
    plate.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 竖向渐变（angle 90：起点色在底部）
    NSGradient(starting: bottomColor, ending: topColor)!.draw(in: plate, angle: 90)

    // 顶部内描边高光，让底板边缘在深色 Dock 上也有层次
    NSGraphicsContext.saveGraphicsState()
    plate.addClip()
    let rim = NSBezierPath(roundedRect: plateRect.insetBy(dx: 2, dy: 2), xRadius: plateRadius - 2, yRadius: plateRadius - 2)
    rim.lineWidth = 4
    NSColor.white.withAlphaComponent(0.18).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // 白色符号，按宽高比适配到底板中央约 68% 的区域
    let config = NSImage.SymbolConfiguration(pointSize: 480, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    else {
        fputs("SF Symbol not found: \(symbolName)\n", stderr)
        exit(1)
    }
    let box: CGFloat = 560
    let ratio = min(box / symbol.size.width, box / symbol.size.height)
    let size = NSSize(width: symbol.size.width * ratio, height: symbol.size.height * ratio)
    let origin = NSPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2 - 6)
    symbol.draw(in: NSRect(origin: origin, size: size))
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / canvas)
    transform.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

let catalog = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "GaplessPaste/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
let fm = FileManager.default
try fm.createDirectory(at: iconSet, withIntermediateDirectories: true)

let info: [String: Any] = ["author": "xcode", "version": 1]
try writeJSON(["info": info], to: catalog.appendingPathComponent("Contents.json"))

var images: [[String: Any]] = []
for slot in slots {
    try renderPNG(pixels: slot.pixels).write(to: iconSet.appendingPathComponent(slot.filename))
    images.append([
        "filename": slot.filename,
        "idiom": "mac",
        "scale": "\(slot.scale)x",
        "size": "\(slot.points)x\(slot.points)",
    ])
}
try writeJSON(["images": images, "info": info], to: iconSet.appendingPathComponent("Contents.json"))
print("wrote \(slots.count) icons to \(iconSet.path)")
