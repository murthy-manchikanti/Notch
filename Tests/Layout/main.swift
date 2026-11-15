import Foundation

func crowded(_ gap: CGFloat, previous: Bool = false) -> Bool {
    MenuSpacePolicy.isCrowded(notchLeft: 600, menuEnd: 600 - gap, trusted: true, wasCrowded: previous)
}
precondition(crowded(20), "Crowded menu must move artwork to the right")
precondition(!crowded(60, previous: true), "Clear menu must restore left artwork")
precondition(crowded(40, previous: true), "Small menu changes must not flicker the dot")
precondition(!crowded(40), "Small menu changes must not flicker the thumbnail")
precondition(crowded(-10), "Menu overlapping the notch must use the dot")
precondition(MenuSpacePolicy.isCrowded(notchLeft: 600, menuEnd: nil, trusted: true, wasCrowded: false))
precondition(MenuSpacePolicy.isCrowded(notchLeft: 600, menuEnd: 100, trusted: false, wasCrowded: false))
precondition(!MenuSpacePolicy.isCrowded(notchLeft: -600, menuEnd: -660, trusted: true, wasCrowded: true), "Negative display coordinates must work")
print("Passed 8 menu-space layout checks")

let screen = CGRect(x: 0, y: 0, width: 1400, height: 900)
let menus = [
    MenuEntry(title: "App", frame: CGRect(x: 45, y: 0, width: 80, height: 28)),
    MenuEntry(title: "Help", frame: CGRect(x: 440, y: 0, width: 50, height: 28)),
    MenuEntry(title: "Status", frame: CGRect(x: 1250, y: 0, width: 30, height: 28), isExtra: true)
]
precondition(MenuSpacePolicy.menuEnd(menus, screen: screen, primaryTop: 900, menuHeight: 32) == 490, "Status items must not force right placement")
precondition(!MenuSpacePolicy.isCrowded(notchLeft: 600, menuEnd: 490, trusted: true, wasCrowded: true))
let second = CGRect(x: -1400, y: 100, width: 1400, height: 900)
let secondMenus = [MenuEntry(title: "Help", frame: CGRect(x: -950, y: -100, width: 50, height: 28))]
precondition(MenuSpacePolicy.menuEnd(secondMenus, screen: second, primaryTop: 900, menuHeight: 32) == -900, "Negative multi-display coordinates must work")
precondition(MenuSpacePolicy.menuEnd(menus, screen: second, primaryTop: 900, menuHeight: 32) == nil, "Another display's menus must not affect this display")
precondition(MenuSpacePolicy.menuEnd([MenuEntry(title: "Unknown", frame: .zero)], screen: screen, primaryTop: 900, menuHeight: 32) == nil)
print("Passed 5 menu-geometry regression checks")

precondition(!MenuSpacePolicy.hasReadableGeometry([]))
precondition(!MenuSpacePolicy.hasReadableGeometry([MenuEntry(title: "Empty", frame: .zero)]))
precondition(!MenuSpacePolicy.hasReadableGeometry([menus[2]]))
let unnamed = MenuEntry(title: "", frame: CGRect(x: 500, y: 0, width: 40, height: 28))
precondition(MenuSpacePolicy.hasReadableGeometry([unnamed]))
precondition(MenuSpacePolicy.menuEnd([unnamed], screen: screen, primaryTop: 900, menuHeight: 32) == 540)
let invalid = MenuEntry(title: "Invalid", frame: CGRect(x: CGFloat.infinity, y: 0, width: 40, height: 28))
precondition(!MenuSpacePolicy.hasReadableGeometry([invalid]))
print("Passed 6 Accessibility geometry checks")

precondition(MenuSpacePolicy.mergesIndicatorsIntoNotch(bundleIdentifier: "com.apple.iWork.Numbers"))
precondition(!MenuSpacePolicy.mergesIndicatorsIntoNotch(bundleIdentifier: "com.apple.Safari"))
precondition(!MenuSpacePolicy.mergesIndicatorsIntoNotch(bundleIdentifier: nil))
print("Passed 3 Numbers-only indicator checks")

precondition(MenuSpacePolicy.indicatorRowHeight(safeAreaTop: 32, visibleTopInset: 40, fallback: 22) == 32)
precondition(MenuSpacePolicy.indicatorRowHeight(safeAreaTop: 0, visibleTopInset: 30, fallback: 22) == 30)
precondition(MenuSpacePolicy.indicatorRowHeight(safeAreaTop: 0, visibleTopInset: 0, fallback: 24) == 24)
precondition(MenuSpacePolicy.indicatorDiameter(rowHeight: 32, hasNotch: true) == 22)
for height: CGFloat in [22, 24, 30, 32] {
    let diameter = MenuSpacePolicy.indicatorDiameter(rowHeight: height, hasNotch: false)
    precondition(diameter <= 22 && (height - diameter) / 2 >= 4)
}
print("Passed 8 external-display indicator checks")

precondition(!MenuSpacePolicy.canShowDetachedDot(onRight: true, rightFree: false), "Music and connection dots must hide on a blocked right side")
precondition(MenuSpacePolicy.canShowDetachedDot(onRight: true, rightFree: true))
precondition(MenuSpacePolicy.canShowDetachedDot(onRight: false, rightFree: false), "A free left dot need not hide when only the right side is blocked")
let dot = CGRect(x: 810, y: 5, width: 22, height: 22)
let windowMenu = MenuEntry(title: "Window", frame: CGRect(x: 815, y: 0, width: 60, height: 32))
precondition(MenuSpacePolicy.dotOverlapsMenu([windowMenu], dot: dot), "App-menu geometry must detect a menu underneath our own overlay")
precondition(!MenuSpacePolicy.dotOverlapsMenu([MenuEntry(title: "Help", frame: CGRect(x: 850, y: 0, width: 40, height: 32))], dot: dot))
precondition(MenuSpacePolicy.dotOverlapsMenu([MenuEntry(title: "", frame: windowMenu.frame)], dot: dot))
precondition(!MenuSpacePolicy.dotOverlapsMenu([MenuEntry(title: "Other screen", frame: CGRect(x: 815, y: -900, width: 60, height: 32))], dot: dot))
precondition(!MenuSpacePolicy.dotOverlapsMenu([MenuEntry(title: "Invalid", frame: .zero)], dot: dot))
print("Passed 8 blocked-dot visibility and overlap checks")
