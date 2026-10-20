import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make-dmg-background.swift <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 1_280
let height = 840

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: red / 255,
        green: green / 255,
        blue: blue / 255,
        alpha: alpha
    )
}

func drawCentered(
    _ value: String,
    y: CGFloat,
    font: NSFont,
    color: NSColor
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let size = (value as NSString).size(withAttributes: attributes)
    (value as NSString).draw(
        at: NSPoint(x: (CGFloat(width) - size.width) / 2, y: y),
        withAttributes: attributes
    )
}

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fatalError("Could not create the DMG background canvas")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [
    color(250, 252, 255),
    color(238, 245, 255),
    color(248, 250, 253)
])?.draw(in: canvas, angle: -90)

let glow = NSBezierPath(ovalIn: NSRect(x: 240, y: 310, width: 800, height: 420))
color(73, 141, 255, 0.065).setFill()
glow.fill()

let topRule = NSBezierPath(roundedRect: NSRect(x: 500, y: 754, width: 280, height: 7),
                           xRadius: 3.5, yRadius: 3.5)
color(35, 107, 238, 0.82).setFill()
topRule.fill()

drawCentered(
    "Routekeeper",
    y: 690,
    font: .systemFont(ofSize: 48, weight: .semibold),
    color: color(30, 41, 59)
)
drawCentered(
    "拖动到右侧「应用程序」文件夹",
    y: 650,
    font: .systemFont(ofSize: 25, weight: .regular),
    color: color(91, 107, 128)
)

// The two icons are positioned over this arrow by Finder.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 510, y: 485))
arrow.line(to: NSPoint(x: 746, y: 485))
arrow.lineWidth = 7
arrow.lineCapStyle = .round
color(35, 107, 238, 0.8).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 724, y: 509))
arrowHead.line(to: NSPoint(x: 756, y: 485))
arrowHead.line(to: NSPoint(x: 724, y: 461))
arrowHead.lineWidth = 7
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
color(35, 107, 238, 0.8).setStroke()
arrowHead.stroke()

let panel = NSBezierPath(
    roundedRect: NSRect(x: 128, y: 58, width: 1024, height: 190),
    xRadius: 26,
    yRadius: 26
)
color(255, 255, 255, 0.78).setFill()
panel.fill()
color(35, 107, 238, 0.12).setStroke()
panel.lineWidth = 2
panel.stroke()

drawCentered(
    "安装后将 Routekeeper 拖入「应用程序」，再从那里启动",
    y: 186,
    font: .systemFont(ofSize: 28, weight: .medium),
    color: color(31, 47, 70)
)
drawCentered(
    "首次打开如被 macOS 拦截，请前往「系统设置 → 隐私与安全性」允许打开",
    y: 130,
    font: .systemFont(ofSize: 22, weight: .regular),
    color: color(74, 91, 113)
)
drawCentered(
    "支持 Apple Silicon · macOS 14 或更高版本",
    y: 88,
    font: .systemFont(ofSize: 20, weight: .medium),
    color: color(96, 112, 132)
)

NSGraphicsContext.restoreGraphicsState()

// Keep 2× pixels while presenting at the Finder window's 640×420 pt size.
bitmap.size = NSSize(width: CGFloat(width) / 2, height: CGFloat(height) / 2)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the DMG background")
}
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)
