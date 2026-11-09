import Foundation

/// Where Wren is. `auto` follows what you're doing.
enum SceneKind: String, CaseIterable, Identifiable {
    case auto, room, code, library, beach
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .room: return "Cozy room"
        case .code: return "Code den"
        case .library: return "Library"
        case .beach: return "Beach"
        }
    }
}

/// The time of day, as the window sees it.
enum DayPeriod: String, CaseIterable {
    case dawn, morning, day, golden, dusk, night

    static func at(_ date: Date, calendar: Calendar = .current) -> DayPeriod {
        let h = calendar.component(.hour, from: date)
        switch h {
        case 5..<7: return .dawn
        case 7..<11: return .morning
        case 11..<16: return .day
        case 16..<19: return .golden
        case 19..<21: return .dusk
        default: return .night
        }
    }

    var lampOn: Bool { self == .dusk || self == .night || self == .dawn }
}

/// A cozy little room, 96 x 48: window, desk, lamp, plant, shelf and fairy lights, with Wren at the desk.
enum RoomScene {
    static let width = 96
    static let height = 48

    static func palette(_ period: DayPeriod) -> Palette {
        var p = Wren.palette
        // Room colours dim and warm as the day goes on.
        let wallDay = RGBA(0xead7b8), wallNight = RGBA(0x3a2e3a)
        let dim: Double
        switch period {
        case .dawn: dim = 0.55
        case .morning: dim = 0.05
        case .day: dim = 0
        case .golden: dim = 0.18
        case .dusk: dim = 0.6
        case .night: dim = 0.85
        }
        func shade(_ c: RGBA) -> RGBA { c.mixed(RGBA(0x241b26), dim * 0.75) }
        p["1"] = wallDay.mixed(wallNight, dim)                // wall
        p["2"] = shade(RGBA(0xdcc5a2))                        // wall stripe
        p["3"] = shade(RGBA(0xb98b62))                        // wainscot
        p["4"] = shade(RGBA(0x8c5b3d))                        // floor
        p["5"] = shade(RGBA(0x75492f))                        // floor plank line
        p["6"] = shade(RGBA(0x9b6a45))                        // desk top
        p["7"] = shade(RGBA(0x6e472f))                        // desk front
        p["8"] = shade(RGBA(0x53351f))                        // desk shadow / legs
        p["9"] = shade(RGBA(0xf3e7cf))                        // window frame
        p["0"] = shade(RGBA(0x3d2f45))                        // chair
        p["!"] = shade(RGBA(0x2c2232))                        // chair shade
        p["@"] = shade(RGBA(0x6fa069))                        // leaf
        p["#"] = shade(RGBA(0x4b7a4a))                        // leaf dark
        p["$"] = shade(RGBA(0xc4744a))                        // pot
        p["%"] = shade(RGBA(0xa55b36))                        // pot shade
        p["^"] = shade(RGBA(0x7b4f35))                        // shelf
        p["&"] = shade(RGBA(0xc8553d)); p["*"] = shade(RGBA(0x3f7f8c)); p["("] = shade(RGBA(0xe2b04a)); p[")"] = shade(RGBA(0x8a6fb0))
        p["-"] = RGBA(0x2b2a2f)                               // lamp metal
        p["+"] = period.lampOn ? RGBA(0xffe3a3) : RGBA(0xd9c8a6) // lamp shade
        p["="] = RGBA(0xfff1c9, alpha: period.lampOn ? 0.28 : 0) // lamp glow
        p["~"] = RGBA(0xfff4d6, alpha: period == .day || period == .morning ? 0.22 : period == .golden ? 0.25 : 0) // sunbeam
        p["{"] = RGBA(0xffd27a); p["}"] = RGBA(0xff9fb0); p["|"] = RGBA(0x8fd3ff); p["<"] = RGBA(0x4a3f3a) // fairy bulbs, wire
        p[">"] = shade(RGBA(0xd8c7a8))                        // poster paper
        p["?"] = shade(RGBA(0x7aa6b8)); p["/"] = shade(RGBA(0xe39b6a)) // poster art
        p[";"] = RGBA(0xf3ede1); p[":"] = RGBA(0x8a5a2b)        // desk mug, coffee
        // Sky.
        let sky: (RGBA, RGBA)
        switch period {
        case .dawn: sky = (RGBA(0x6c6aa8), RGBA(0xf2a68a))
        case .morning: sky = (RGBA(0x8cc4ea), RGBA(0xd7eef7))
        case .day: sky = (RGBA(0x5fa8e0), RGBA(0xb5dcf3))
        case .golden: sky = (RGBA(0xe9935a), RGBA(0xf8d48b))
        case .dusk: sky = (RGBA(0x3c3a78), RGBA(0xc76d7e))
        case .night: sky = (RGBA(0x10162e), RGBA(0x253058))
        }
        p["Á"] = sky.0; p["É"] = sky.0.mixed(sky.1, 0.25); p["Í"] = sky.0.mixed(sky.1, 0.5); p["Ó"] = sky.0.mixed(sky.1, 0.75); p["Ú"] = sky.1
        p["☼"] = period == .night || period == .dusk ? RGBA(0xf4f1dc) : RGBA(0xfff0b0)   // sun or moon
        p["·"] = RGBA(0xfafaff, alpha: 0.9)                    // stars
        p["≈"] = RGBA(0xffffff, alpha: period == .night ? 0 : 0.8) // clouds
        // Code den, library and beach.
        p["α"] = RGBA(0x7fd38a); p["β"] = RGBA(0x7db7da); p["γ"] = RGBA(0xe9a35a); p["δ"] = RGBA(0xc49be0); p["ε"] = RGBA(0x6b7480)
        p["θ"] = RGBA(0x0d1117); p["ι"] = RGBA(0x16202c); p["κ"] = RGBA(0x2a2f36)
        p["μ"] = RGBA(0xff6b9a); p["ν"] = RGBA(0x6be4ff); p["ξ"] = RGBA(0xb48cff)
        p["λ"] = RGBA(0x3f8f5a)
        let night = period == .night || period == .dusk
        p["ο"] = night ? RGBA(0x15264a) : (period == .golden || period == .dawn ? RGBA(0x3a6f8f) : RGBA(0x2f86b8)) // sea
        p["π"] = night ? RGBA(0x22396a) : (period == .golden || period == .dawn ? RGBA(0x5f97ad) : RGBA(0x4fa6d4)) // sea light
        p["ρ"] = RGBA(0xf4f1e8, alpha: night ? 0.5 : 0.95)                                       // foam
        p["σ"] = shade(RGBA(0xecd3a0)); p["τ"] = shade(RGBA(0xd8b980)); p["υ"] = shade(RGBA(0xc7a56a)) // sand, speckle, wet sand
        p["φ"] = shade(RGBA(0x8a5a36)); p["χ"] = shade(RGBA(0x5f8f43)); p["ψ"] = shade(RGBA(0x3f6f33)) // palm trunk, fronds
        p["ω"] = shade(RGBA(0xd9533f)); p["ϑ"] = shade(RGBA(0xf6efdc)); p["ϒ"] = shade(RGBA(0xc49a6c)) // umbrella stripes, crate
        p["ϖ"] = RGBA(0x2a2a2e)                                                                  // gull
        return p
    }

    /// The whole scene for one tick.
    static func frame(activity: Activity, tick: Int, period: DayPeriod, musicPlaying: Bool, scene: SceneKind = .room) -> PixelGrid {
        if scene == .beach { return beach(activity: activity, tick: tick, period: period, musicPlaying: musicPlaying) }
        var g = PixelGrid(width: width, height: height, fill: "1")
        // Wall stripes and wainscot.
        for x in stride(from: 3, to: width, by: 12) { g.fill(x, 0, 1, 34, "2") }
        g.fill(0, 34, width, 1, "3")
        g.fill(0, 35, width, 13, "4")
        for (i, y) in [37, 40, 43, 46].enumerated() {
            g.fill(0, y, width, 1, "5")
            for x in stride(from: (i * 7) % 16, to: width, by: 16) { g.set(x, y + 1, "5"); g.set(x, y + 2, "5") }
        }

        drawWindow(&g, period: period, tick: tick)
        drawFairyLights(&g, tick: tick, period: period)
        if scene == .library {
            drawLibraryShelves(&g)
        } else {
            drawShelf(&g)
            if scene != .code { drawPoster(&g) }
        }

        // Sunbeam falling across the floor from the window.
        if period == .day || period == .morning || period == .golden {
            for y in 35..<48 {
                let x0 = 6 + (y - 35) * 2
                for x in x0..<(x0 + 20) where g[x, y] != "." { g.set(x, y, mixBeam(g[x, y])) }
            }
        }

        // Chair behind Wren.
        g.fill(37, 24, 22, 12, "0")
        g.fill(37, 24, 22, 1, "!"); g.fill(37, 24, 1, 12, "!"); g.fill(58, 24, 1, 12, "!")
        g.fill(36, 26, 1, 10, "!"); g.fill(59, 26, 1, 10, "!")

        // Wren, sitting so the bottom of the sprite meets the desk.
        let wren = Wren.frame(activity, tick: tick, bob: musicPlaying && activity != .chilling && activity != .idle)
        g.blit(wren, x: 37, y: 19)

        // Desk: top, front, legs.
        g.fill(14, 37, 70, 2, "6")
        g.fill(14, 39, 70, 5, "7")
        g.fill(14, 39, 70, 1, "8")
        g.fill(16, 44, 3, 4, "8"); g.fill(79, 44, 3, 4, "8")
        g.fill(20, 41, 14, 1, "8"); g.set(26, 42, "6"); g.set(27, 42, "6") // drawer and handle

        if scene == .code {
            drawMonitors(&g, tick: tick)
            drawLEDStrip(&g, tick: tick)
        } else {
            drawLamp(&g, period: period)
            drawDeskThings(&g, tick: tick, activity: activity)
        }
        drawPlant(&g, tick: tick)
        return g
    }

    // MARK: Code den

    /// A cheap repeatable hash for procedural detail.
    private static func hash(_ a: Int, _ b: Int) -> Int {
        var h = UInt32(truncatingIfNeeded: a &* 374_761_393 &+ b &* 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Int(h ^ (h >> 16))
    }

    private static func drawMonitors(_ g: inout PixelGrid, tick: Int) {
        // Left: an editor with code scrolling up. Right: a terminal with a blinking cursor.
        for (x0, terminal) in [(12, false), (64, true)] {
            let w = 22, h = 14, y0 = 20
            g.fill(x0 - 1, y0 - 1, w + 2, h + 2, "κ")
            g.fill(x0, y0, w, h, terminal ? "θ" : "ι")
            g.fill(x0 + w / 2 - 1, y0 + h + 1, 2, 2, "κ"); g.fill(x0 + w / 2 - 4, y0 + h + 3, 8, 1, "κ")
            let scroll = tick / 2
            for row in 0..<(h / 2) {
                let line = row + scroll
                let y = y0 + 1 + row * 2
                if terminal {
                    let len = 4 + hash(line, 7) % 14
                    g.set(x0 + 1, y, "α")
                    for i in 0..<min(len, w - 4) where hash(line, i) % 5 != 0 { g.set(x0 + 3 + i, y, i < 3 ? "α" : "ε") }
                    if row == h / 2 - 1 && tick % 2 == 0 { g.fill(x0 + 3 + min(len, w - 5), y, 1, 1, "α") }
                } else {
                    let indent = (hash(line, 3) % 3) * 2
                    var x = x0 + 2 + indent
                    var word = 0
                    while x < x0 + w - 2 && word < 4 {
                        let len = 2 + hash(line, word) % 5
                        let color: Character = ["β", "γ", "δ", "α", "ε"][hash(line, word + 9) % 5]
                        for i in 0..<len where x + i < x0 + w - 1 { g.set(x + i, y, color) }
                        x += len + 1
                        word += 1
                    }
                }
            }
        }
    }

    private static func drawLEDStrip(_ g: inout PixelGrid, tick: Int) {
        let colors: [Character] = ["μ", "ξ", "ν"]
        for x in 14..<84 { g.set(x, 36, colors[((x + tick) / 6) % 3]) }
    }

    // MARK: Library

    private static func drawLibraryShelves(_ g: inout PixelGrid) {
        let books: [Character] = ["&", "*", "(", ")", "@", ">", "%"]
        for shelfY in stride(from: 9, through: 33, by: 8) {
            var x = 36
            while x < 95 {
                let w = 1 + hash(x, shelfY) % 2
                let h = 4 + hash(shelfY, x) % 3
                if hash(x, shelfY + 1) % 9 != 0 { g.fill(x, shelfY - h, w, h, books[hash(x, shelfY + 2) % books.count]) }
                x += w
            }
            g.fill(35, shelfY, 61, 1, "^")
        }
        g.fill(35, 1, 1, 33, "^"); g.fill(95, 1, 1, 33, "^")
    }

    // MARK: Beach

    static func beach(activity: Activity, tick: Int, period: DayPeriod, musicPlaying: Bool) -> PixelGrid {
        var g = PixelGrid(width: width, height: height, fill: "σ")
        let bands: [Character] = ["Á", "É", "Í", "Ó", "Ú"]
        for y in 0..<23 { g.fill(0, y, width, 1, bands[min(4, y * 5 / 23)]) }
        let night = period == .night || period == .dusk
        if night {
            g.fill(70, 4, 5, 5, "☼"); g.fill(69, 5, 2, 3, bands[0])
            for (i, s) in [(8, 3), (20, 7), (33, 2), (47, 9), (58, 4), (86, 8), (26, 13)].enumerated() where (tick / 3 + i) % 5 != 0 {
                g.set(s.0, s.1, "·")
            }
        } else {
            let sunY = period == .golden || period == .dawn ? 15 : 4
            g.fill(68, sunY, 6, 6, "☼"); g.fill(67, sunY + 1, 8, 4, "☼")
            let drift = (tick / 5) % 120
            for (dx, dy, len) in [(0, 6, 9), (3, 5, 4), (40, 10, 7), (43, 9, 3)] {
                for i in 0..<len { g.set((drift + dx + i) % 120 - 12, dy, "≈") }
            }
            // A gull gliding across.
            let gx = (tick * 2) % 160 - 20
            g.set(gx, 8, "ϖ"); g.set(gx + 1, 7, "ϖ"); g.set(gx + 2, 8, "ϖ"); g.set(gx + 3, 7, "ϖ"); g.set(gx + 4, 8, "ϖ")
        }
        // Sea with drifting highlights, a moon or sun path, then foam and wet sand.
        g.fill(0, 23, width, 10, "ο")
        for row in 0..<5 {
            let y = 24 + row * 2
            let shift = (tick + row * 3) % 12
            for x in stride(from: -12 + shift + row * 5, to: width, by: 12) { g.fill(x, y, 3 + row, 1, "π") }
        }
        if night || period == .golden {
            for y in stride(from: 24, to: 33, by: 2) { g.fill(68 + (y + tick) % 3, y, 4, 1, night ? "ρ" : "☼") }
        }
        let foam = (tick / 2) % 4
        for x in 0..<width { g.set(x, 33 + ((x / 5 + foam) % 3 == 0 ? 1 : 0), "ρ") }
        g.fill(0, 34, width, 2, "υ")
        for i in 0..<70 { g.set(hash(i, 1) % width, 37 + hash(i, 2) % 11, "τ") }

        drawPalm(&g, tick: tick)
        drawUmbrella(&g)

        // Wren on a beach chair behind a driftwood crate.
        g.fill(36, 25, 24, 12, "ω"); g.fill(36, 25, 24, 1, "ϑ")
        for x in stride(from: 36, to: 60, by: 4) { g.fill(x, 26, 2, 11, "ϑ") }
        let wren = Wren.frame(activity, tick: tick, bob: musicPlaying && activity != .chilling && activity != .idle)
        g.blit(wren, x: 37, y: 19)
        g.fill(26, 37, 46, 6, "ϒ"); g.fill(26, 37, 46, 1, "6"); g.fill(26, 40, 46, 1, "φ")
        g.fill(28, 43, 3, 5, "φ"); g.fill(67, 43, 3, 5, "φ")
        // Coconut drink with a straw.
        g.fill(64, 33, 5, 4, "φ"); g.fill(65, 32, 3, 1, "ϑ"); g.set(67, 30, "ω"); g.set(68, 29, "ω")
        return g
    }

    private static func drawPalm(_ g: inout PixelGrid, tick: Int) {
        let sway = (tick / 4) % 2
        // Trunk curving up from the sand.
        for y in 14..<44 {
            let x = 10 + (44 - y) / 6
            g.fill(x, y, 3, 1, "φ")
            if y % 3 == 0 { g.set(x, y, "8"); g.set(x + 2, y, "8") }
        }
        let top = (15, 13)
        let fronds: [(Int, Int)] = [(-1, 0), (1, 0), (-1, 1), (1, 1), (0, -1)]
        for (dx, dy) in fronds {
            for i in 0..<10 {
                let x = top.0 + dx * i + (dy == -1 ? 0 : sway)
                let y = top.1 + dy * i / 2 + (abs(dx) == 1 ? i * i / 18 : -i / 2)
                g.fill(x, y, 2, 1, i % 3 == 0 ? "ψ" : "χ")
                if i > 1 && i < 8 { g.fill(x, y + 1, 2, 1, "ψ") }
            }
        }
        g.fill(14, 14, 2, 2, "φ"); g.fill(16, 15, 2, 2, "φ")
    }

    private static func drawUmbrella(_ g: inout PixelGrid) {
        g.fill(84, 14, 1, 30, "φ")
        for row in 0..<6 {
            let half = 4 + row * 2
            for x in (84 - half)...(84 + half) {
                g.set(x, 10 + row, ((x - 84 + 40) / 4) % 2 == 0 ? "ω" : "ϑ")
            }
        }
        // A towel on the sand.
        g.fill(76, 42, 16, 4, "β"); for x in stride(from: 77, to: 92, by: 3) { g.fill(x, 42, 1, 4, "ϑ") }
    }

    private static func mixBeam(_ c: Character) -> Character {
        // A lighter key per surface: reuse the stripe for wall, desk top for floor.
        switch c {
        case "4", "5": return "6"
        case "1": return "2"
        default: return c
        }
    }

    private static func drawWindow(_ g: inout PixelGrid, period: DayPeriod, tick: Int) {
        let x = 6, y = 5, w = 24, h = 22
        g.fill(x - 1, y - 1, w + 2, h + 2, "9")
        let bands: [Character] = ["Á", "É", "Í", "Ó", "Ú"]
        for row in 0..<h { g.fill(x, y + row, w, 1, bands[min(4, row * 5 / h)]) }
        switch period {
        case .night, .dusk:
            // Moon and a few twinkling stars.
            g.fill(x + 16, y + 3, 4, 4, "☼"); g.set(x + 16, y + 3, bands[0]); g.set(x + 19, y + 6, bands[0])
            g.fill(x + 15, y + 4, 2, 2, bands[0])
            let stars = [(2, 2), (7, 5), (11, 1), (4, 10), (21, 11), (13, 8), (9, 14)]
            for (i, s) in stars.enumerated() where period == .night || i % 2 == 0 {
                if (tick / 3 + i) % 5 != 0 { g.set(x + s.0, y + s.1, "·") }
            }
        case .dawn, .golden:
            g.fill(x + 3, y + h - 6, 5, 3, "☼"); g.fill(x + 4, y + h - 7, 3, 1, "☼")
        case .morning, .day:
            g.fill(x + 17, y + 2, 4, 4, "☼"); g.fill(x + 16, y + 3, 6, 2, "☼")
            // Clouds drift slowly.
            let drift = (tick / 6) % (w + 8)
            let cx = x + (drift % (w + 8)) - 6
            for (dx, dy, len) in [(0, 9, 7), (2, 8, 3), (8, 13, 5)] {
                for i in 0..<len where cx + dx + i >= x && cx + dx + i < x + w { g.set(cx + dx + i, y + dy, "≈") }
            }
        }
        // Rooftops of the town outside.
        let skyline = [3, 3, 5, 5, 5, 2, 2, 4, 4, 6, 6, 6, 3, 3, 3, 5, 5, 2, 2, 4, 4, 4, 3, 3]
        for (i, hgt) in skyline.enumerated() { g.fill(x + i, y + h - hgt, 1, hgt, period == .night || period == .dusk ? "0" : "!") }
        if period == .night || period == .dusk {
            for (i, wx) in [2, 9, 16, 20].enumerated() where (tick / 8 + i) % 3 != 0 { g.set(x + wx, y + h - 2, "{") }
        }
        // Frame cross and sill.
        g.fill(x + w / 2 - 1, y, 2, h, "9")
        g.fill(x, y + h / 2 - 1, w, 1, "9")
        g.fill(x - 2, y + h + 1, w + 4, 2, "3")
    }

    private static func drawFairyLights(_ g: inout PixelGrid, tick: Int, period: DayPeriod) {
        let bulbs: [Character] = ["{", "}", "|"]
        var i = 0
        for x in stride(from: 34, to: 94, by: 1) {
            let sag = Int((sin(Double(x - 34) / 60 * .pi * 3).magnitude) * 3)
            g.set(x, 2 + sag, "<")
            if (x - 34) % 6 == 3 {
                let on = !period.lampOn || (tick / 2 + i) % 4 != 0
                g.set(x, 3 + sag, on ? bulbs[i % 3] : "<")
                i += 1
            }
        }
    }

    private static func drawShelf(_ g: inout PixelGrid) {
        g.fill(64, 15, 26, 1, "^"); g.fill(66, 16, 1, 2, "^"); g.fill(87, 16, 1, 2, "^")
        let books: [(Character, Int)] = [("&", 7), ("*", 6), ("(", 8), (")", 7), ("&", 5), ("*", 7), ("(", 6)]
        var x = 66
        for (c, h) in books { g.fill(x, 15 - h, 2, h, c); x += 2 }
        // A leaning book and a tiny cactus.
        g.set(81, 9, ")"); g.set(81, 10, ")"); g.fill(82, 11, 1, 4, ")"); g.fill(83, 13, 1, 2, ")")
        g.fill(85, 12, 2, 3, "$"); g.fill(85, 9, 2, 3, "@"); g.set(84, 10, "@")
    }

    private static func drawPoster(_ g: inout PixelGrid) {
        // A little framed mountain print.
        g.fill(68, 19, 16, 11, "3"); g.fill(69, 20, 14, 9, ">")
        for i in 0..<6 { g.fill(70 + i, 27 - i, 12 - 2 * i, 1, "?") }
        g.fill(78, 25, 4, 1, "?"); g.fill(79, 24, 2, 1, "?")
        g.fill(71, 21, 2, 2, "/")
    }

    private static func drawLamp(_ g: inout PixelGrid, period: DayPeriod) {
        // Glow pool on the desk and wall when the lamp is on.
        if period.lampOn {
            for y in 22..<37 {
                let spread = (y - 22) / 2 + 3
                for x in (27 - spread)...(27 + spread) { if g[x, y] != "." { g.set(x, y, glow(g[x, y])) } }
            }
        }
        g.fill(22, 36, 8, 1, "-")
        g.fill(25, 26, 1, 10, "-")
        g.fill(25, 25, 6, 1, "-")
        g.fill(28, 21, 6, 1, "+"); g.fill(27, 22, 8, 1, "+"); g.fill(26, 23, 10, 2, "+")
        if period.lampOn { g.fill(28, 25, 6, 1, "=") }
    }

    private static func glow(_ c: Character) -> Character {
        switch c {
        case "1": return "2"
        case "6": return "+"
        default: return c
        }
    }

    private static func drawDeskThings(_ g: inout PixelGrid, tick: Int, activity: Activity) {
        // A stack of books and a mug of coffee on the right.
        g.fill(64, 33, 10, 2, "*"); g.fill(65, 31, 9, 2, "&"); g.fill(64, 29, 10, 2, "(")
        g.fill(66, 34, 6, 1, ">")
        g.fill(77, 32, 4, 5, ";"); g.fill(77, 32, 4, 1, ":"); g.fill(81, 33, 1, 2, ";")
        if activity != .breakTime {
            let s = tick % 2
            g.set(78 + s, 30, "o"); g.set(79 - s, 29, "o")
        }
    }

    private static func drawPlant(_ g: inout PixelGrid, tick: Int) {
        // A leafy pot plant on the floor to the right; the top leaves sway a pixel.
        let sway = (tick / 4) % 2
        // Stems.
        for (x0, y0, x1) in [(89, 39, 86), (90, 39, 92), (89, 39, 89)] {
            for y in stride(from: y0, to: y0 - 9, by: -1) {
                let t = Double(y0 - y) / 9
                g.set(x0 + Int(Double(x1 - x0) * t), y, "#")
            }
        }
        let leaf = [".@@@.", "@@#@@", "@@@@#", ".@@@."]
        let small = [".@@.", "@@#@", ".@@."]
        let spots: [(Int, Int, Bool)] = [(84, 28, true), (90, 26, true), (86, 33, false), (91, 32, true), (87, 22, false), (82, 34, false)]
        for (i, (x, y, big)) in spots.enumerated() {
            let dx = y < 30 ? sway : 0
            g.blit(big ? leaf : small, x: x + dx + (i % 2 == 0 ? 0 : 0), y: y)
        }
        g.fill(86, 40, 8, 7, "$"); g.fill(85, 38, 10, 2, "%"); g.fill(86, 46, 8, 1, "%")
        g.fill(87, 42, 6, 1, "%")
    }
}
