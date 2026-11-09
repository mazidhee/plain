import AppKit

/// Where the notch is, from the screen's safe area and the two menu bar areas beside it.
struct NotchGeometry: Equatable {
    /// The screen the island lives on (global coordinates).
    var screenFrame: CGRect
    /// The notch cut-out in global coordinates; nil on screens without one.
    var notch: CGRect?
    /// Menu bar height on that screen.
    var menuBarHeight: CGFloat

    var hasNotch: Bool { notch != nil }
    /// Height the pill hugs: the notch's, or a slim pill under the menu bar.
    var barHeight: CGFloat { notch?.height ?? 30 }
    var notchWidth: CGFloat { notch?.width ?? 0 }
    var centerX: CGFloat { notch?.midX ?? screenFrame.midX }
    /// The top edge the island hangs from.
    var topY: CGFloat { hasNotch ? screenFrame.maxY : screenFrame.maxY - menuBarHeight - 6 }

    /// The notch rect from raw screen values. Pure, so it is unit-tested.
    static func notchRect(frame: CGRect, safeTop: CGFloat, leftArea: CGRect, rightArea: CGRect) -> CGRect? {
        guard safeTop > 0, leftArea.width > 0, rightArea.width > 0 else { return nil }
        // The aux areas are the menu bar strips either side of the notch. They may come back in
        // screen-local or global coordinates; their widths are what matter.
        let minX = frame.minX + leftArea.width
        let maxX = frame.maxX - rightArea.width
        guard maxX > minX else { return nil }
        return CGRect(x: minX, y: frame.maxY - safeTop, width: maxX - minX, height: safeTop)
    }

    static func of(_ screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let notch = notchRect(frame: frame, safeTop: screen.safeAreaInsets.top,
                              leftArea: screen.auxiliaryTopLeftArea ?? .zero, rightArea: screen.auxiliaryTopRightArea ?? .zero)
        let menuBar = max(24, frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(screenFrame: frame, notch: notch, menuBarHeight: menuBar)
    }

    /// The built-in (notched) screen if there is one, else the main screen.
    static func current() -> NotchGeometry? {
        let screens = NSScreen.screens
        if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) { return of(notched) }
        return (NSScreen.main ?? screens.first).map(of)
    }

    static func describe() -> String {
        NSScreen.screens.enumerated().map { i, s in
            let g = of(s)
            return """
            screen \(i): \(s.localizedName) frame=\(s.frame) visible=\(s.visibleFrame) scale=\(s.backingScaleFactor)
              safeAreaInsets=\(s.safeAreaInsets) auxLeft=\(String(describing: s.auxiliaryTopLeftArea)) auxRight=\(String(describing: s.auxiliaryTopRightArea))
              notch=\(String(describing: g.notch)) menuBar=\(g.menuBarHeight)
            """
        }.joined(separator: "\n")
    }
}
