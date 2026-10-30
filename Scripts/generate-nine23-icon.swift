// Run from the repository root with `swift Scripts/generate-nine23-icon.swift`.
// Vector wordmark rendered at each asset's native resolution; no external artwork.
import AppKit
import Foundation
import CoreText

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
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let width = Double(size)
        context.setFillColor(CGColor(red: 9/255, green: 12/255, blue: 14/255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: width))
        let baseFont = NSFont.systemFont(ofSize: width * 0.32, weight: .heavy)
        let font = NSFontManager.shared.convert(baseFont, toHaveTrait: [.condensedFontMask, .italicFontMask])
        let attrs: [NSAttributedString.Key: Any] = [.font: font,
            .foregroundColor: NSColor.white, .kern: -width * 0.012]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "9:23", attributes: attrs))
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.textPosition = CGPoint(x: (width - bounds.width) / 2 - bounds.minX, y: (width - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, context)
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: root + "/" + filename))
    }
}
