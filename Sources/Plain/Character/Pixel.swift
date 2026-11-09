import AppKit
import SwiftUI

/// A colour for one pixel. Kept as plain bytes so frames render straight into a bitmap.
struct RGBA: Hashable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    init(_ hex: UInt32, alpha: Double = 1) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
        a = UInt8(max(0, min(1, alpha)) * 255)
    }

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Linear mix towards another colour, t in 0...1.
    func mixed(_ other: RGBA, _ t: Double) -> RGBA {
        let t = max(0, min(1, t))
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(Double(x) + (Double(y) - Double(x)) * t) }
        return RGBA(r: m(r, other.r), g: m(g, other.g), b: m(b, other.b), a: m(a, other.a))
    }

    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255) }
    var nsColor: NSColor { NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255) }
}

typealias Palette = [Character: RGBA]

/// A grid of palette keys. "." is transparent. Art is written as rows of strings, so a sprite
/// reads like the picture it draws.
struct PixelGrid: Equatable {
    let width: Int
    let height: Int
    private(set) var cells: [Character]

    static let clear: Character = "."

    init(width: Int, height: Int, fill: Character = PixelGrid.clear) {
        self.width = width
        self.height = height
        cells = Array(repeating: fill, count: width * height)
    }

    init(rows: [String]) {
        let w = rows.map(\.count).max() ?? 0
        self.init(width: w, height: rows.count)
        blit(rows, x: 0, y: 0)
    }

    subscript(x: Int, y: Int) -> Character {
        get { (x >= 0 && y >= 0 && x < width && y < height) ? cells[y * width + x] : PixelGrid.clear }
        set { if x >= 0 && y >= 0 && x < width && y < height { cells[y * width + x] = newValue } }
    }

    mutating func set(_ x: Int, _ y: Int, _ c: Character) { self[x, y] = c }

    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Character) {
        for yy in y..<(y + h) { for xx in x..<(x + w) { self[xx, yy] = c } }
    }

    /// Paints rows of art; "." leaves what is underneath.
    mutating func blit(_ rows: [String], x: Int, y: Int) {
        for (dy, row) in rows.enumerated() {
            for (dx, c) in row.enumerated() where c != PixelGrid.clear && c != " " {
                self[x + dx, y + dy] = c
            }
        }
    }

    mutating func blit(_ grid: PixelGrid, x: Int, y: Int) {
        for yy in 0..<grid.height { for xx in 0..<grid.width {
            let c = grid[xx, yy]
            if c != PixelGrid.clear { self[x + xx, y + yy] = c }
        } }
    }

    /// Replaces one key with another everywhere (e.g. a lens catching screen light).
    mutating func replace(_ from: Character, with to: Character) {
        for i in cells.indices where cells[i] == from { cells[i] = to }
    }

    func count(of c: Character) -> Int { cells.filter { $0 == c }.count }

    /// Adds a 1-pixel outline of `key` around the silhouette (4-neighbour), so dark art
    /// stays readable on a dark menu bar.
    func outlined(with key: Character) -> PixelGrid {
        var out = self
        for y in 0..<height { for x in 0..<width where self[x, y] == PixelGrid.clear {
            if [(1, 0), (-1, 0), (0, 1), (0, -1)].contains(where: { self[x + $0.0, y + $0.1] != PixelGrid.clear }) {
                out[x, y] = key
            }
        } }
        return out
    }
}

enum PixelRenderer {
    /// Renders each cell as a `scale` x `scale` block of device pixels. No smoothing, ever.
    static func cgImage(_ grid: PixelGrid, palette: Palette, scale: Int = 1, alphaMap: [Character: Double]? = nil, tint: RGBA? = nil) -> CGImage? {
        let w = grid.width * scale, h = grid.height * scale
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let key = grid[x, y]
                guard key != PixelGrid.clear else { continue }
                var px: RGBA
                if let alphaMap {
                    let a = alphaMap[key] ?? 1
                    guard a > 0 else { continue }
                    px = tint ?? RGBA(0x000000)
                    px.a = UInt8(a * 255)
                } else {
                    guard let c = palette[key] else { continue }
                    px = c
                }
                guard px.a > 0 else { continue }
                // Premultiplied alpha.
                let a = Double(px.a) / 255
                let r = UInt8(Double(px.r) * a), g = UInt8(Double(px.g) * a), b = UInt8(Double(px.b) * a)
                for sy in 0..<scale {
                    var i = ((y * scale + sy) * w + x * scale) * 4
                    for _ in 0..<scale {
                        bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = px.a
                        i += 4
                    }
                }
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// An NSImage `pointsPerPixel` points per cell, with crisp 1x, 2x and 3x representations.
    static func nsImage(_ grid: PixelGrid, palette: Palette, pointsPerPixel: Int = 1, alphaMap: [Character: Double]? = nil, tint: RGBA? = nil, template: Bool = false) -> NSImage {
        let size = NSSize(width: grid.width * pointsPerPixel, height: grid.height * pointsPerPixel)
        let image = NSImage(size: size)
        for s in [1, 2, 3] {
            if let cg = cgImage(grid, palette: palette, scale: pointsPerPixel * s, alphaMap: alphaMap, tint: tint) {
                let rep = NSBitmapImageRep(cgImage: cg)
                rep.size = size
                image.addRepresentation(rep)
            }
        }
        image.isTemplate = template
        return image
    }
}

/// Shows a grid in SwiftUI, scaled by whole numbers with no interpolation.
struct PixelView: View {
    let grid: PixelGrid
    let palette: Palette
    var pixel: CGFloat = 4

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Pre-scale to whole device pixels so nothing downstream can smooth the edges.
        let device = max(1, Int((pixel * max(1, displayScale)).rounded()))
        if let cg = PixelRenderer.cgImage(grid, palette: palette, scale: device) {
            Image(decorative: cg, scale: CGFloat(device) / pixel)
                .interpolation(.none)
                .frame(width: CGFloat(grid.width) * pixel, height: CGFloat(grid.height) * pixel)
        } else {
            Color.clear.frame(width: CGFloat(grid.width) * pixel, height: CGFloat(grid.height) * pixel)
        }
    }
}
