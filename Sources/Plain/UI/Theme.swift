import SwiftUI

/// Warm, cozy colours. Plain always uses its own dark-roast look so the pixel art glows.
enum Theme {
    static let bg = Color(hex: 0x1C1613)
    static let card = Color(hex: 0x29201B)
    static let cardHi = Color(hex: 0x352a23)
    static let line = Color(hex: 0x3f322a)
    static let text = Color(hex: 0xF4E8D4)
    static let textInk = RGBA(0xF4E8D4)
    /// The clock while paused: dimmed, so the state reads from across the room.
    static let pausedInk = RGBA(0x6E5F52)
    static let muted = Color(hex: 0xB49F88)
    static let faint = Color(hex: 0x7d6b5c)
    static let accent = Color(hex: 0xF2B35A)
    static let accentDeep = Color(hex: 0xD9774A)
    static let good = Color(hex: 0x9BC485)
    static let study = Color(hex: 0x7DB7DA)

    static func color(_ c: Category) -> Color {
        switch c {
        case .work: return Color(hex: 0xE9A35A)
        case .study: return Color(hex: 0x7DB7DA)
        case .exam: return Color(hex: 0xE5735F)
        case .reading: return Color(hex: 0x9BC485)
        case .chilling: return Color(hex: 0xB8A0E3)
        }
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// A rounded chip used for categories, durations and sources.
struct Chip: View {
    let label: String
    var selected = false
    var tint: Color = Theme.accent
    var action: () -> Void

    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.value } nonmutating set { hoverBox.value = newValue } }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.rounded(12, selected ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(selected ? Theme.bg : Theme.text.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? tint : (hover ? Theme.line : Theme.cardHi))
                )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
    }
}

/// A round icon button for the timer controls.
struct RoundButton: View {
    let symbol: String
    var label: String? = nil
    var prominent = false
    var size: CGFloat = 34
    var action: () -> Void
    @StateObject private var hoverBox = Box(false)
    private var hover: Bool { get { hoverBox.value } nonmutating set { hoverBox.value = newValue } }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: size * 0.38, weight: .bold))
                if let label { Text(label).font(Theme.rounded(12, .semibold)) }
            }
            .foregroundStyle(prominent ? Theme.bg : Theme.text)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, label == nil ? 0 : 10)
            .background(Capsule().fill(prominent ? Theme.accent : (hover ? Theme.cardHi : Theme.card)))
            .scaleEffect(hover ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
        .help(label ?? "")
    }
}

/// A chunky pixel progress bar.
struct PixelProgress: View {
    let value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let cells = max(1, Int(geo.size.width / 6))
            let lit = Int((Double(cells) * min(1, max(0, value))).rounded(.down))
            HStack(spacing: 2) {
                ForEach(0..<cells, id: \.self) { i in
                    Rectangle().fill(i < lit ? tint : Theme.line)
                }
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// The countdown in the 3 x 5 pixel font.
struct PixelClock: View {
    let text: String
    var pixel: CGFloat = 4
    var color: Color = Theme.text
    /// Exact ink, drawn into the pixels (reliable everywhere, unlike a colour multiply).
    var ink: RGBA? = nil

    var body: some View {
        let g = PixelFont.grid(text)
        if let ink {
            PixelView(grid: g, palette: ["#": ink], pixel: pixel)
        } else {
            PixelView(grid: g, palette: ["#": RGBA(0xFFFFFF)], pixel: pixel).colorMultiply(color)
        }
    }
}

/// View-local state. (`@State` is a compiler macro in this SDK, and the Command Line Tools ship
/// without the SwiftUI macro plugin, so local state lives in a tiny observable box instead.)
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}
