import Foundation

/// What the character is doing. Each maps to a little looping animation.
enum Activity: String, CaseIterable, Codable {
    case work, lockIn, study, exam, breakTime = "break", chilling, idle

    var label: String {
        switch self {
        case .work: return "Work"
        case .lockIn: return "Lock in"
        case .study: return "Study"
        case .exam: return "Exam"
        case .breakTime: return "Break"
        case .chilling: return "Chilling"
        case .idle: return "Idle"
        }
    }

    /// Frames per second. Exams scribble faster; dozing is slow.
    var fps: Double {
        switch self {
        case .exam: return 6
        case .idle: return 2
        case .breakTime, .chilling: return 3
        default: return 4
        }
    }
}

/// Wren: a sleepy-smart student with dark skin, a big round afro, thick glasses and a terracotta
/// hoodie. Drawn on a 22 x 18 canvas: head on top (rows 0-12), shoulders and props below.
enum Wren {
    static let width = 22
    static let height = 18

    static let palette: Palette = [
        "H": RGBA(0x1d1614), "h": RGBA(0x4f3b31),           // afro and beard, highlight
        "s": RGBA(0x8a5634), "S": RGBA(0x6e4127),           // skin, shade (ears, hands)
        "r": RGBA(0x9a5b3c),                                // cheek warmth
        "k": RGBA(0x0e0a09), "w": RGBA(0xe4f1f4),           // glasses rims, lens
        "p": RGBA(0x120d0c), "m": RGBA(0x4e2418),           // pupil, mouth
        "E": RGBA(0x2e1a12),                                // closed eyelid line
        "G": RGBA(0xbfe6ff), "F": RGBA(0xfbfbf8),           // lens in screen glow, fogged lens
        "c": RGBA(0xc9693f), "C": RGBA(0x9e4f2d), "d": RGBA(0xf4e4c6), // hoodie, shade, strings
        "L": RGBA(0x4f5862), "l": RGBA(0x95a3ae), "K": RGBA(0x353c44), // laptop edge, lid, base
        "y": RGBA(0xf2c94c), "i": RGBA(0xe86a8a),           // stickers
        "P": RGBA(0xf6efdc), "x": RGBA(0xb9aa8f), "b": RGBA(0x6d4a35), "B": RGBA(0x2f6f6a), // book
        "n": RGBA(0xf2c94c), "t": RGBA(0x3a302a),           // pencil, tip
        "q": RGBA(0x8fd3ff),                                // sweat drop
        "u": RGBA(0x6cc0ae), "U": RGBA(0x3b8c7c), "e": RGBA(0x8a5a2b), // mug, shade, tea
        "o": RGBA(0xe6e0d6, alpha: 0.85),                   // steam
        "Y": RGBA(0x5fb8a5), "M": RGBA(0x3b8c7c),           // headphones
        "N": RGBA(0xf2c94c), "Z": RGBA(0xbcd3f2),           // music notes, z's
        "O": RGBA(0xfff3dc, alpha: 0.38),                   // soft halo for dark menu bars
    ]

    /// How strongly each key shows in the monochrome (template) menu bar version.
    static let templateAlpha: [Character: Double] = [
        "H": 1, "h": 0.85, "s": 0.3, "S": 0.5, "r": 0.42, "k": 1, "w": 0, "G": 0.12, "F": 0.55,
        "p": 1, "E": 0.9, "m": 0.95, "c": 0.62, "C": 0.85, "d": 0.2, "L": 1, "l": 0.72, "K": 1, "y": 0.2, "i": 0.2,
        "P": 0.3, "x": 0.85, "b": 1, "B": 1, "n": 0.8, "t": 1, "q": 0.9, "u": 0.55, "U": 1, "e": 1,
        "o": 0.55, "Y": 0.5, "M": 1, "N": 1, "Z": 1,
    ]

    // Head, 18 x 13: a round afro framing the face. Lenses sit at columns 4-6 and 11-13 of row 8.
    static let head: [String] = [
        "....HH.HHHH.HH....",
        "..HHHHHHHHHHHHHH..",
        ".HHHhHHHHHHhHHHHH.",
        "HHHHHHHHhHHHHHHhHH",
        "HHhHHHHHHHHHHHHHHH",
        "HHHHHHHhHHHHHhHHHH",
        "HHHHssssssssssHHHH",
        "HHHskkksssskkksHHH",
        "HHSkwwwkkkkwwwkSHH",
        ".HsskkksssskkkssH.",
        "..HsrssssssssrsH..",
        "...HssssmmssssH...",
        "....HHssssssHH....",
    ]

    enum Eyes { case open, left, right, closed, happy }

    /// Builds one frame. `tick` counts up at the activity's fps; `bob` nods the head to music.
    static func frame(_ activity: Activity, tick: Int, bob: Bool = false) -> PixelGrid {
        var g = PixelGrid(width: width, height: height)
        var headY = 0
        var eyes: Eyes = (tick % 17 == 16) ? .closed : .open
        var mouth: [Int]? = nil
        var lens: Character = "w"
        var smile = false

        switch activity {
        case .chilling: headY = (tick / 2) % 2; eyes = .happy
        case .idle: headY = 1; eyes = .closed
        default: if bob { headY = (tick / 2) % 2 }
        }

        drawBody(&g)

        // Props that sit behind the head go first; most sit in front, after it.
        var head = PixelGrid(rows: Self.head)
        switch activity {
        case .work, .lockIn:
            lens = "G"
        case .study:
            let scan = (tick / 2) % 3
            eyes = tick % 8 == 5 ? .closed : (scan == 0 ? .left : scan == 1 ? .open : .right)
        case .exam:
            eyes = .open
            mouth = [7, 8, 9, 10]
        case .breakTime:
            let sipping = tick % 6 < 3
            eyes = sipping ? .closed : (tick % 6 == 5 ? .closed : .open)
            if sipping { lens = "F" }
        case .chilling:
            smile = true
        case .idle:
            mouth = [8, 9]
        }

        head.replace("w", with: lens)
        drawEyes(&head, eyes, lens: lens)
        if let mouth {
            head.fill(4, 11, 10, 1, "s")
            for x in mouth { head.set(x, 11, "m") }
        }
        if smile {
            head.fill(4, 11, 10, 1, "s")
            head.set(7, 11, "m"); head.set(10, 11, "m"); head.set(8, 12, "m"); head.set(9, 12, "m")
        }
        g.blit(head, x: 2, y: headY)

        switch activity {
        case .work: drawLaptop(&g, tick: tick)
        case .lockIn:
            drawLaptop(&g, tick: tick)
            drawHeadphones(&g, tick: tick, headY: headY, notes: false)
        case .study: drawBook(&g, tick: tick)
        case .exam: drawExam(&g, tick: tick, headY: headY)
        case .breakTime: drawTea(&g, tick: tick)
        case .chilling: drawHeadphones(&g, tick: tick, headY: headY)
        case .idle: drawSleep(&g, tick: tick)
        }
        return g
    }

    private static func drawEyes(_ head: inout PixelGrid, _ eyes: Eyes, lens: Character) {
        switch eyes {
        case .open: head.set(5, 8, "p"); head.set(12, 8, "p")
        case .left: head.set(4, 8, "p"); head.set(11, 8, "p")
        case .right: head.set(6, 8, "p"); head.set(13, 8, "p")
        case .closed:
            for x in [4, 5, 6, 11, 12, 13] { head.set(x, 8, "E") }
        case .happy:
            // Upturned arcs: the outer lens pixels dark, the middle one lifted.
            for x in [4, 6, 11, 13] { head.set(x, 8, "E") }
            head.set(5, 8, lens); head.set(12, 8, lens)
            head.set(5, 7, "E"); head.set(12, 7, "E")
        }
    }

    private static func drawBody(_ g: inout PixelGrid) {
        // Hood collar and neck.
        g.fill(6, 12, 10, 1, "c"); g.set(6, 12, "C"); g.set(15, 12, "C")
        g.fill(9, 12, 4, 1, "s")
        // Shoulders widen as they go down.
        g.fill(3, 13, 16, 1, "c"); g.set(3, 13, "C"); g.set(18, 13, "C")
        g.fill(2, 14, 18, 1, "c"); g.set(2, 14, "C"); g.set(19, 14, "C")
        g.fill(2, 15, 18, 1, "c"); g.set(2, 15, "C"); g.set(19, 15, "C")
        g.fill(1, 16, 20, 2, "c"); g.fill(1, 16, 1, 2, "C"); g.fill(20, 16, 1, 2, "C")
        // Hood bunched beside the chin, a V at the neck, short drawstrings.
        g.fill(5, 11, 2, 2, "C"); g.fill(15, 11, 2, 2, "C")
        g.set(9, 13, "C"); g.set(12, 13, "C")
        g.set(10, 14, "d"); g.set(11, 14, "d")
        g.set(9, 15, "d"); g.set(12, 15, "d")
    }

    private static func drawLaptop(_ g: inout PixelGrid, tick: Int) {
        // The back of the lid faces us, with two stickers.
        g.fill(6, 12, 10, 5, "L")
        g.fill(7, 13, 8, 3, "l")
        g.set(9, 14, "y"); g.set(12, 13, "i"); g.set(13, 13, "i")
        g.fill(4, 17, 14, 1, "K")
        // Hands tap in turn: left up, both down, right up, both down.
        let phase = tick % 4
        let leftY = phase == 0 ? 15 : 16
        let rightY = phase == 2 ? 15 : 16
        g.fill(4, leftY, 2, 1, "S"); g.fill(16, rightY, 2, 1, "S")
        if leftY == 15 { g.set(4, 16, "c"); g.set(5, 16, "c") }
        if rightY == 15 { g.set(16, 16, "c"); g.set(17, 16, "c") }
    }

    private static func drawBook(_ g: inout PixelGrid, tick: Int) {
        let flip = tick % 12
        let left = flip >= 11 || flip < 1 ? ["PxPxxP", "PxxxPP"] : ["PxxxxP", "PxxPxP"]
        // Pages, spine and cover edge.
        g.fill(4, 14, 14, 3, "P")
        g.fill(10, 14, 2, 3, "b")
        g.fill(4, 17, 14, 1, "B")
        g.blit(left.map { String($0.map { $0 == "P" ? "." : $0 }) }, x: 4, y: 15)
        g.blit(["xxxxP", "xxPxx"].map { String($0.map { $0 == "P" ? "." : $0 }) }, x: 12, y: 15)
        // A page lifts at the spine, arcs over and lands.
        switch flip {
        case 8: g.fill(11, 11, 1, 3, "P"); g.fill(12, 13, 4, 1, "P")
        case 9: g.fill(10, 11, 2, 1, "P"); g.fill(10, 12, 1, 2, "P")
        case 10: g.fill(6, 12, 4, 1, "P"); g.set(9, 13, "P")
        default: break
        }
        g.fill(3, 15, 1, 2, "S"); g.fill(18, 15, 1, 2, "S")
    }

    private static func drawExam(_ g: inout PixelGrid, tick: Int, headY: Int) {
        g.fill(5, 15, 11, 3, "P")
        g.fill(6, 16, 6, 1, "x"); g.fill(6, 17, 4, 1, "x")
        // Scribbling back and forth across the page.
        let xs = [9, 11, 13, 10, 12, 14]
        let px = xs[tick % xs.count]
        let up = tick % 2 == 0
        g.set(px, up ? 15 : 16, "t")
        g.set(px + 1, up ? 14 : 15, "n"); g.set(px + 2, up ? 13 : 14, "n")
        g.fill(px + 2, up ? 14 : 15, 2, 1, "S")
        g.fill(4, 16, 2, 1, "S")
        // A sweat drop slides down the temple, then starts again.
        let drop = tick % 5
        if drop < 4 {
            g.set(20, 5 + drop + headY, "q")
            if drop > 0 { g.set(20, 4 + drop + headY, "q") }
        }
    }

    private static func drawTea(_ g: inout PixelGrid, tick: Int) {
        let sipping = tick % 6 < 3
        let top = sipping ? 9 : 13
        // Mug: rim, tea, body, handle.
        g.fill(9, top, 4, 1, "U")
        g.fill(10, top, 2, 1, "e")
        g.fill(9, top + 1, 4, 2, "u")
        g.set(12, top + 2, "U")
        g.set(13, top + 1, "U")
        if sipping {
            g.fill(8, 12, 1, 2, "S"); g.fill(13, 12, 1, 2, "S")
        } else {
            g.set(8, top + 1, "S"); g.set(8, top + 2, "S"); g.set(14, top + 1, "S")
        }
        // Steam curls upwards, swaying.
        if !sipping {
            let sway = tick % 2
            g.set(10 + sway, top - 1, "o"); g.set(11 - sway, top - 2, "o"); g.set(10 + sway, top - 3, "o")
        } else {
            let sway = tick % 2
            g.set(17 + sway, 6, "o"); g.set(18 - sway, 5, "o")
        }
    }

    private static func drawHeadphones(_ g: inout PixelGrid, tick: Int, headY: Int, notes: Bool = true) {
        let y = headY
        // Band pressed into the afro, cups over the ears.
        g.fill(6, y + 1, 10, 1, "Y")
        g.set(5, y + 2, "Y"); g.set(16, y + 2, "Y")
        g.fill(4, y + 3, 1, 3, "Y"); g.fill(17, y + 3, 1, 3, "Y")
        g.fill(2, y + 6, 3, 4, "M"); g.fill(17, y + 6, 3, 4, "M")
        g.set(3, y + 7, "Y"); g.set(18, y + 7, "Y")
        guard notes else { return }
        // Notes drift up beside the head.
        let n = tick % 6
        g.blit([".N", ".N", "NN"], x: 20, y: 7 - n)
        if n >= 3 { g.blit(["N", "N"], x: 0, y: 10 - n) }
        // Hands folded.
        g.fill(8, 16, 2, 1, "S"); g.fill(12, 16, 2, 1, "S")
    }

    private static func drawSleep(_ g: inout PixelGrid, tick: Int) {
        // Arms folded on the desk.
        g.fill(3, 16, 16, 2, "C")
        g.fill(5, 16, 2, 1, "S"); g.fill(15, 16, 2, 1, "S")
        let z = tick % 4
        g.blit(["ZZZ", "..Z", ".Z.", "Z..", "ZZZ"].map { String($0) }, x: 18, y: 7 - z)
        if z >= 2 { g.blit(["ZZZZ", "..Z.", ".Z..", "ZZZZ"], x: 18, y: max(0, 3 - (z - 2) * 2)) }
    }
}
