import Foundation

/// A tiny 3 x 5 pixel font for countdowns, so the clock matches the art.
enum PixelFont {
    static let glyphs: [Character: [String]] = [
        "0": ["###", "#.#", "#.#", "#.#", "###"],
        "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["###", "..#", "###", "#..", "###"],
        "3": ["###", "..#", ".##", "..#", "###"],
        "4": ["#.#", "#.#", "###", "..#", "..#"],
        "5": ["###", "#..", "###", "..#", "###"],
        "6": ["###", "#..", "###", "#.#", "###"],
        "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"],
        "9": ["###", "#.#", "###", "..#", "###"],
        ":": [".", "#", ".", "#", "."],
        "+": ["...", ".#.", "###", ".#.", "..."],
        "-": ["...", "...", "###", "...", "..."],
        "m": ["...", "##.", "###", "#.#", "#.#"],
        "h": ["#..", "#..", "###", "#.#", "#.#"],
        " ": ["..", "..", "..", "..", ".."],
        "^": ["..#..", ".###.", "#.#.#", "..#..", "..#.."],
    ]

    /// Renders text into a grid using `ink` for lit pixels, 1 pixel between glyphs.
    static func grid(_ text: String, ink: Character = "#") -> PixelGrid {
        let chars = text.compactMap { glyphs[$0] }
        let width = chars.reduce(0) { $0 + $1[0].count } + max(0, chars.count - 1)
        var g = PixelGrid(width: max(1, width), height: 5)
        var x = 0
        for rows in chars {
            g.blit(rows.map { String($0.map { $0 == "#" ? ink : "." }) }, x: x, y: 0)
            x += rows[0].count + 1
        }
        return g
    }
}
