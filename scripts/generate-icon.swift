import AppKit

// Original Craft-series menu bar artwork. No third-party assets.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let directory = output.deletingLastPathComponent().appendingPathComponent("BartenderCraft.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let u = CGFloat(pixels) / 1024
        let tile = NSBezierPath(roundedRect: CGRect(x: 72*u, y: 72*u, width: 880*u, height: 880*u), xRadius: 204*u, yRadius: 204*u)
        NSGradient(starting: NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.26, alpha: 1), ending: NSColor(calibratedRed: 0.03, green: 0.46, blue: 0.51, alpha: 1))!.draw(in: tile, angle: 65)
        let bar = NSBezierPath(roundedRect: CGRect(x: 220*u, y: 360*u, width: 584*u, height: 300*u), xRadius: 58*u, yRadius: 58*u)
        NSColor.white.withAlphaComponent(0.96).setFill(); bar.fill()
        let row = NSBezierPath(roundedRect: CGRect(x: 258*u, y: 558*u, width: 508*u, height: 62*u), xRadius: 18*u, yRadius: 18*u)
        NSColor(calibratedRed: 0.05, green: 0.51, blue: 0.56, alpha: 1).setFill(); row.fill()
        for x in [290, 342, 394] {
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: CGRect(x: CGFloat(x)*u, y: 579*u, width: 20*u, height: 20*u)).fill()
        }
        for (x, width) in [(270, 74), (367, 126), (516, 238)] {
            NSColor(calibratedRed: 0.07, green: 0.20, blue: 0.30, alpha: 0.90).setFill()
            NSBezierPath(roundedRect: CGRect(x: CGFloat(x)*u, y: 408*u, width: CGFloat(width)*u, height: 108*u), xRadius: 22*u, yRadius: 22*u).fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", directory.path, "-o", output.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
