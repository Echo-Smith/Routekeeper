import AppKit

let destination = CommandLine.arguments[1]
let folder = URL(fileURLWithPath: destination)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func color(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedWhite: white, alpha: alpha)
}

func shieldPath(in rect: NSRect) -> NSBezierPath {
    let x = rect.minX
    let y = rect.minY
    let width = rect.width
    let height = rect.height
    func point(_ px: CGFloat, _ py: CGFloat) -> NSPoint {
        NSPoint(x: x + width * px, y: y + height * py)
    }

    let path = NSBezierPath()
    path.move(to: point(0.50, 0.925))
    path.curve(to: point(0.84, 0.795),
               controlPoint1: point(0.62, 0.885),
               controlPoint2: point(0.74, 0.835))
    path.curve(to: point(0.79, 0.405),
               controlPoint1: point(0.87, 0.665),
               controlPoint2: point(0.86, 0.515))
    path.curve(to: point(0.50, 0.145),
               controlPoint1: point(0.70, 0.295),
               controlPoint2: point(0.59, 0.205))
    path.curve(to: point(0.21, 0.405),
               controlPoint1: point(0.41, 0.205),
               controlPoint2: point(0.30, 0.295))
    path.curve(to: point(0.16, 0.795),
               controlPoint1: point(0.14, 0.515),
               controlPoint2: point(0.13, 0.665))
    path.curve(to: point(0.50, 0.925),
               controlPoint1: point(0.26, 0.835),
               controlPoint2: point(0.38, 0.885))
    path.close()
    return path
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon canvas unavailable") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.shouldAntialias = true

        let size = CGFloat(pixels)
        let inset = size * 0.055
        let rect = NSRect(x: inset, y: inset, width: CGFloat(pixels) - 2 * inset, height: CGFloat(pixels) - 2 * inset)
        let shape = NSBezierPath(
            roundedRect: rect,
            xRadius: size * 0.205,
            yRadius: size * 0.205
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
        shadow.shadowBlurRadius = size * 0.045
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
        shadow.set()
        color(0.18).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        // A frosted silver tile with a raised, translucent shield.
        NSGradient(colors: [color(0.98), color(0.79), color(0.94)])?
            .draw(in: shape, angle: -65)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let glow = NSPoint(x: rect.minX, y: rect.maxY)
        NSGradient(starting: color(1, 0.95), ending: color(1, 0))?
            .draw(fromCenter: glow, radius: 0, toCenter: glow,
                  radius: rect.width, options: [])
        let reflection = NSBezierPath()
        reflection.move(to: NSPoint(x: rect.minX, y: rect.midY))
        reflection.curve(to: NSPoint(x: rect.maxX, y: rect.maxY * 0.75),
                         controlPoint1: NSPoint(x: rect.midX, y: rect.midY),
                         controlPoint2: NSPoint(x: rect.midX, y: rect.maxY * 0.85))
        reflection.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        reflection.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        reflection.close()
        NSGradient(starting: color(1, 0.45), ending: color(1, 0.02))?
            .draw(in: reflection, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        color(1, 0.85).setStroke()
        shape.lineWidth = max(1, size * 0.003)
        shape.stroke()

        // Half-filled shield: one clear mark, with the glass visible on the right.
        let shield = shieldPath(in: rect.insetBy(dx: rect.width * 0.18,
                                                dy: rect.height * 0.18))
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size / 2, height: size)).addClip()
        color(0.19).setFill()
        shield.fill()
        NSGraphicsContext.restoreGraphicsState()
        color(0.19).setStroke()
        shield.lineWidth = max(1.2, size * 0.026)
        shield.lineJoinStyle = .round
        shield.stroke()

        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
        try png.write(to: folder.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}
