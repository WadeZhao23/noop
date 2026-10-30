// Run from the repository root with `swift Scripts/generate-nine23-icon.swift`.
// Vector wordmark rendered at each asset's native resolution; no external artwork.
import AppKit
import Foundation

let roots = ["StrandiOS/Resources/Assets.xcassets/AppIcon.appiconset",
             "StrandiOS/Resources/Assets.xcassets/AppIcon-Navy.appiconset",
             "NOOPWatch/Assets.xcassets/AppIcon.appiconset",
             "Strand/Resources/Assets.xcassets/AppIcon.appiconset"]
for root in roots {
    let data = try Data(contentsOf: URL(fileURLWithPath: root + "/Contents.json"))
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    for item in json["images"] as! [[String: Any]] {
        guard let filename = item["filename"] as? String else { continue }
        let points = Double((item["size"] as? String ?? "1024x1024").split(separator: "x")[0])!
        let scale = Double((item["scale"] as? String ?? "1x").replacingOccurrences(of: "x", with: ""))!
        let size = Int(points * scale)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let width = Double(size)
        NSColor(srgbRed: 29/255, green: 30/255, blue: 35/255, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: width)).fill()
        let font = NSFont.monospacedDigitSystemFont(ofSize: width * 0.31, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font,
            .foregroundColor: NSColor(srgbRed: 105/255, green: 221/255, blue: 184/255, alpha: 1)]
        let word = "9:23" as NSString
        let textSize = word.size(withAttributes: attrs)
        word.draw(at: NSPoint(x: (width - textSize.width) / 2, y: (width - textSize.height) / 2), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: root + "/" + filename))
    }
}
