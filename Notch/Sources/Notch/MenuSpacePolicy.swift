import Foundation
import CoreGraphics

struct MenuEntry: Equatable {
    let title: String
    let frame: CGRect
    var isExtra = false
}

enum MenuSpacePolicy {
    static func canShowDetachedDot(onRight: Bool, rightFree: Bool) -> Bool {
        !onRight || rightFree
    }

    static func dotOverlapsMenu(_ entries: [MenuEntry], dot: CGRect) -> Bool {
        entries.contains {
            validFrame($0.frame) && $0.frame.insetBy(dx: -4, dy: -2).intersects(dot)
        }
    }

    static func indicatorRowHeight(safeAreaTop: CGFloat, visibleTopInset: CGFloat, fallback: CGFloat) -> CGFloat {
        if safeAreaTop > 0 { return safeAreaTop }
        return visibleTopInset > 0 ? visibleTopInset : fallback
    }

    static func indicatorDiameter(rowHeight: CGFloat, hasNotch: Bool) -> CGFloat {
        // External menu bars can be shorter than the MacBook's notch area.
        // Leave four points above and below the indicator on flat displays.
        hasNotch ? 22 : min(22, max(1, rowHeight - 8))
    }

    /// Numbers can place app menus on both sides of the physical notch.
    /// Keep the collapsed indicator inside the hardware area instead of covering menus.
    static func mergesIndicatorsIntoNotch(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.apple.iWork.Numbers"
    }

    static func hasReadableGeometry(_ entries: [MenuEntry]) -> Bool {
        entries.contains { !$0.isExtra && validFrame($0.frame) }
    }

    private static func validFrame(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite } &&
        frame.width > 0 && frame.height > 0
    }

    /// AX coordinates are global points with a top-left origin. AppKit screen
    /// frames use a bottom-left origin; compare only items on the target menu row.
    static func menuEnd(_ entries: [MenuEntry], screen: CGRect, primaryTop: CGFloat, menuHeight: CGFloat) -> CGFloat? {
        let rowTop = primaryTop - screen.maxY
        return entries.filter {
            !$0.isExtra && validFrame($0.frame) &&
            $0.frame.minY >= rowTop - 2 && $0.frame.minY < rowTop + menuHeight &&
            $0.frame.maxX > screen.minX && $0.frame.minX < screen.maxX
        }.map { $0.frame.maxX }.max()
    }

    static func isCrowded(notchLeft: CGFloat, menuEnd: CGFloat?, trusted: Bool, wasCrowded: Bool) -> Bool {
        // Missing geometry must never put artwork on top of app menus.
        guard trusted, let menuEnd else { return true }
        let space = notchLeft - menuEnd
        // 22-point circle + 8-point notch gap + breathing room. Hysteresis avoids oscillation.
        return space < (wasCrowded ? 46 : 38)
    }
}

enum PrintIndicatorSide: CaseIterable {
    case left
    case right

    func frame(centerX: CGFloat, rowTop: CGFloat, notchWidth: CGFloat, rowHeight: CGFloat) -> CGRect {
        let height = min(22, max(1, rowHeight - 8))
        let edge = notchWidth / 2 + 8
        let width: CGFloat = self == .left ? 54 : 27
        let x = centerX + (self == .left ? -edge - width : edge)
        return CGRect(x: x, y: rowTop + (rowHeight - height) / 2, width: width, height: height)
    }
}
