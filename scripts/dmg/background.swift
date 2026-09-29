// Draws the DMG window's background (KB-233): an arrow from where Finder
// shows KeyBridge to where it shows Applications, and the steps underneath in
// the three languages KeyBridge speaks. Sizes and positions must match
// scripts/dmg/make-dmg.py.
//
//   swift scripts/dmg/background.swift <output folder>
//
// Writes background.png (1x) and background@2x.png; release.sh combines them
// into one TIFF so Finder picks the sharp one on Retina screens.
import AppKit

// The window's content. Its bottom 30 points stay empty: Finder shows its
// path bar there when the user has turned it on everywhere, and a disk
// image's own settings cannot hide it.
let size = NSSize(width: 600, height: 400)
// Icon centres, in points from the top left, as in make-dmg.py.
let appCentre = NSPoint(x: 160, y: 160)
let applicationsCentre = NSPoint(x: 440, y: 160)
let iconSize: CGFloat = 112

// Both steps: dragging only copies, and nothing opens KeyBridge afterwards.
let hints = [
    "Drag KeyBridge to Applications, then open it from there",
    "将 KeyBridge 拖到“应用程序”文件夹，再从那里打开",
    "KeyBridge を「アプリケーション」へドラッグして、そこから開いてください",
]

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Top-left origin, like Finder's icon positions.
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)

    // Light, whatever the Mac's appearance.
    NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.985, blue: 0.995, alpha: 1),
                        NSColor(srgbRed: 0.925, green: 0.94, blue: 0.965, alpha: 1)])!
        .draw(in: NSRect(origin: .zero, size: size), angle: 90)

    // The arrow, between the two icons with some air on either side.
    let accent = NSColor(srgbRed: 0, green: 0.443, blue: 0.890, alpha: 1)  // site --accent-bg
    let start = appCentre.x + iconSize / 2 + 24
    let end = applicationsCentre.x - iconSize / 2 - 24
    let y = appCentre.y
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: start, y: y))
    shaft.line(to: NSPoint(x: end - 6, y: y))
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    accent.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: end - 18, y: y - 14))
    head.line(to: NSPoint(x: end, y: y))
    head.line(to: NSPoint(x: end - 18, y: y + 14))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // The hint, English first and stronger, the others as quieter echoes.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    var top: CGFloat = 268
    for (index, hint) in hints.enumerated() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: index == 0 ? 15 : 13, weight: index == 0 ? .semibold : .regular),
            .foregroundColor: NSColor(white: index == 0 ? 0.16 : 0.42, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: hint, attributes: attributes)
        let height = text.size().height
        // Drawn in a flipped context, so each line is flipped back locally.
        context.cgContext.saveGState()
        context.cgContext.translateBy(x: 0, y: top + height)
        context.cgContext.scaleBy(x: 1, y: -1)
        text.draw(in: NSRect(x: 0, y: 0, width: size.width, height: height))
        context.cgContext.restoreGState()
        top += height + (index == 0 ? 6 : 3)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let folder = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    let data = draw(scale: scale).representation(using: .png, properties: [:])!
    try! data.write(to: folder.appending(path: name))
}
