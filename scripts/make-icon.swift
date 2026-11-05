import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift scripts/make-icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func draw(in context: CGContext, size: CGFloat) {
    let unit = size / 1024
    context.scaleBy(x: unit, y: unit)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.28))
    context.addPath(squircle)
    context.setFillColor(color(0x3A36C9))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x6A8BFF), color(0x4A47E0), color(0x3A2FB8)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(sheen, startCenter: CGPoint(x: 330, y: 860), startRadius: 0, endCenter: CGPoint(x: 330, y: 860), endRadius: 620, options: [])
    context.restoreGState()

    let bubble = CGMutablePath()
    let bubbleRect = CGRect(x: 222, y: 330, width: 580, height: 410)
    bubble.addRoundedRect(in: bubbleRect, cornerWidth: 112, cornerHeight: 112)
    bubble.move(to: CGPoint(x: 300, y: 360))
    bubble.addCurve(to: CGPoint(x: 248, y: 236), control1: CGPoint(x: 300, y: 300), control2: CGPoint(x: 286, y: 256))
    bubble.addCurve(to: CGPoint(x: 420, y: 340), control1: CGPoint(x: 330, y: 250), control2: CGPoint(x: 392, y: 296))
    bubble.closeSubpath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x10104A, 0.35))
    context.addPath(bubble)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    let read = color(0x4A47E0)
    let unread = color(0xD5D8F6)
    let lines: [(y: CGFloat, width: CGFloat, readWidth: CGFloat)] = [
        (626, 408, 408),
        (535, 408, 236),
        (444, 280, 0),
    ]
    for line in lines {
        let x: CGFloat = 308
        let full = CGRect(x: x, y: line.y - 24, width: line.width, height: 48)
        context.addPath(CGPath(roundedRect: full, cornerWidth: 24, cornerHeight: 24, transform: nil))
        context.setFillColor(unread)
        context.fillPath()
        if line.readWidth > 0 {
            let filled = CGRect(x: x, y: line.y - 24, width: line.readWidth, height: 48)
            context.addPath(CGPath(roundedRect: filled, cornerWidth: 24, cornerHeight: 24, transform: nil))
            context.setFillColor(read)
            context.fillPath()
        }
    }
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let side = entry.pixels
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(1) }
    context.interpolationQuality = .high
    draw(in: context, size: CGFloat(side))
    let image = context.makeImage()!
    let representation = NSBitmapImageRep(cgImage: image)
    let data = representation.representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent("\(entry.name).png"))
}
print("Wrote \(sizes.count) images to \(output.path)")
