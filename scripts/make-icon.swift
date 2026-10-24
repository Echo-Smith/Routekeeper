import AppKit

guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
    fputs("Usage: swift scripts/make-icon.swift <output.iconset> [output.icon]\n", stderr)
    exit(1)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let iconPackageDestination = CommandLine.arguments.count == 3
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : nil

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: red / 255,
        green: green / 255,
        blue: blue / 255,
        alpha: alpha
    )
}

// The sidebar icon renders as #62B0F2 in light mode. Keep the icon artwork on
// that exact base and use only restrained lighting so it reads like glass.
let glassBase = color(98, 176, 242)
let glassHighlight = color(122, 190, 248)
let glassShade = color(78, 157, 229)
let glassEdge = color(180, 222, 255, 0.72)

func drawSymbol(in rect: NSRect, pointSize: CGFloat) {
    let configuration = NSImage.SymbolConfiguration(
        pointSize: pointSize,
        weight: .medium
    ).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let symbol = NSImage(
        systemSymbolName: "shield.lefthalf.filled",
        accessibilityDescription: nil
    )?.withSymbolConfiguration(configuration) else {
        fatalError("The Routekeeper shield symbol is unavailable.")
    }

    let symbolRect = NSRect(
        x: rect.midX - symbol.size.width / 2,
        y: rect.midY - symbol.size.height / 2,
        width: symbol.size.width,
        height: symbol.size.height
    )
    symbol.draw(
        in: symbolRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

func drawShieldLayer(pixels: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(
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
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Shield layer canvas unavailable.")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    context.imageInterpolation = .high

    let size = CGFloat(pixels)
    drawSymbol(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        pointSize: size * 0.39
    )

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Shield layer rendering failed.")
    }
    return png
}

func drawIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
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
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Icon canvas unavailable.")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    context.imageInterpolation = .high

    let size = CGFloat(pixels)
    let inset = size * 0.055
    let tile = NSRect(
        x: inset,
        y: inset,
        width: size - 2 * inset,
        height: size - 2 * inset
    )
    let radius = tile.width * 0.285
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = size * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.014)
    shadow.set()
    color(60, 135, 210, 0.9).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()

    NSGradient(colors: [glassHighlight, glassBase, glassShade])?
        .draw(in: tile, angle: -72)

    let upperGlow = NSPoint(
        x: tile.minX + tile.width * 0.18,
        y: tile.maxY - tile.height * 0.12
    )
    NSGradient(
        starting: NSColor.white.withAlphaComponent(0.20),
        ending: NSColor.white.withAlphaComponent(0)
    )?.draw(
        fromCenter: upperGlow,
        radius: 0,
        toCenter: upperGlow,
        radius: tile.width * 0.72,
        options: []
    )

    let lowerShade = NSPoint(
        x: tile.maxX - tile.width * 0.12,
        y: tile.minY + tile.height * 0.08
    )
    NSGradient(
        starting: color(52, 137, 218, 0),
        ending: color(52, 137, 218, 0.12)
    )?.draw(
        fromCenter: lowerShade,
        radius: 0,
        toCenter: lowerShade,
        radius: tile.width * 0.62,
        options: []
    )

    let sheen = NSBezierPath()
    sheen.move(to: NSPoint(x: tile.minX, y: tile.midY + tile.height * 0.08))
    sheen.curve(
        to: NSPoint(x: tile.maxX, y: tile.maxY),
        controlPoint1: NSPoint(x: tile.midX * 0.78, y: tile.maxY * 0.91),
        controlPoint2: NSPoint(x: tile.midX * 1.22, y: tile.maxY * 0.98)
    )
    sheen.line(to: NSPoint(x: tile.maxX, y: tile.maxY))
    sheen.line(to: NSPoint(x: tile.minX, y: tile.maxY))
    sheen.close()
    NSGradient(
        starting: NSColor.white.withAlphaComponent(0.12),
        ending: NSColor.white.withAlphaComponent(0.015)
    )?.draw(in: sheen, angle: -90)

    NSGraphicsContext.restoreGraphicsState()

    glassEdge.setStroke()
    tilePath.lineWidth = max(1, size * 0.0045)
    tilePath.stroke()

    drawSymbol(in: tile, pointSize: tile.width * 20 / 38)

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Icon rendering failed.")
    }
    return png
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(points)x\(points)\(suffix).png"
        try drawIcon(pixels: points * scale)
            .write(to: destination.appendingPathComponent(filename), options: .atomic)
    }
}

if let iconPackageDestination {
    let assets = iconPackageDestination.appendingPathComponent("Assets", isDirectory: true)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try drawShieldLayer(pixels: 1024)
        .write(to: assets.appendingPathComponent("Shield.png"), options: .atomic)

    let manifest: [String: Any] = [
        "fill": [
            "linear-gradient": [
                "extended-srgb:0.47843,0.74510,0.97255,1.00000",
                "extended-srgb:0.30588,0.61569,0.89804,1.00000"
            ],
            "orientation": [
                "start": ["x": 0.08, "y": 0.92],
                "stop": ["x": 0.92, "y": 0.08]
            ]
        ],
        "groups": [
            [
                "layers": [
                    [
                        "glass": true,
                        "hidden": false,
                        "image-name": "Shield.png",
                        "name": "Shield",
                        "opacity": 1,
                        "position": [
                            "scale": 1.6,
                            "translation-in-points": [0, 0]
                        ]
                    ]
                ],
                "lighting": "individual",
                "shadow": [
                    "kind": "neutral",
                    "opacity": 0.3
                ],
                "specular": true,
                "translucency": [
                    "enabled": true,
                    "value": 0.22
                ]
            ]
        ],
        "supported-platforms": [
            "squares": "shared"
        ]
    ]
    let manifestData = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys]
    )
    try manifestData.write(
        to: iconPackageDestination.appendingPathComponent("icon.json"),
        options: .atomic
    )
}
