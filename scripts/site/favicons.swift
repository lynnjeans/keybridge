// Renders the website's bitmap icons from site/favicon.svg (SK-293), for the
// crawlers and devices that don't read an SVG icon: Bing, iOS home screens,
// older browsers, and anything that asks for /favicon.ico.
//
//   swift scripts/site/favicons.swift
//
// Writes, next to favicon.svg in site/:
//   favicon.ico            16, 32 and 48 px, each stored as a PNG
//   icon-192.png           for Google and Android
//   apple-touch-icon.png   180 px, for iOS, square: iOS rounds the corners
//                          itself and would show transparent ones as black
//
// Run it again whenever favicon.svg changes (scripts/icons/infinity.py).

import AppKit

let site = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "site")
guard let svg = NSImage(contentsOf: site.appendingPathComponent("favicon.svg")) else {
    fatalError("Could not read \(site.path)/favicon.svg")
}

/// favicon.svg's gradient, from its <linearGradient id="fill">: light at the
/// top, full blue from 70% down.
let backdrop = NSGradient(colorsAndLocations:
    (NSColor(srgbRed: 0x0a / 255, green: 0x5f / 255, blue: 0xd8 / 255, alpha: 1), 0),
    (NSColor(srgbRed: 0x0a / 255, green: 0x5f / 255, blue: 0xd8 / 255, alpha: 1), 0.3),
    (NSColor(srgbRed: 0x4a / 255, green: 0xa8 / 255, blue: 0xff / 255, alpha: 1), 1))!

func png(_ size: Int, square: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    if square { backdrop.draw(in: rect, angle: 90) }
    svg.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// An ICO file whose images are PNGs, which every browser since IE Vista reads.
func ico(_ sizes: [Int]) -> Data {
    var data = Data()
    func le16(_ v: Int) { data.append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8 & 0xff)]) }
    func le32(_ v: Int) { le16(v & 0xffff); le16(v >> 16) }
    let images = sizes.map { png($0) }
    le16(0); le16(1); le16(sizes.count)
    var offset = 6 + 16 * sizes.count
    for (size, image) in zip(sizes, images) {
        data.append(UInt8(size % 256)); data.append(UInt8(size % 256))
        data.append(0); data.append(0)
        le16(1); le16(32); le32(image.count); le32(offset)
        offset += image.count
    }
    images.forEach { data.append($0) }
    return data
}

let files: [(String, Data)] = [
    ("favicon.ico", ico([16, 32, 48])),
    ("icon-192.png", png(192)),
    ("apple-touch-icon.png", png(180, square: true)),
]
for (name, data) in files {
    try! data.write(to: site.appendingPathComponent(name))
    print("\(name)  \(data.count) bytes")
}
