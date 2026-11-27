import AppKit
import SwiftUI
import Combine
import ApplicationServices

final class NotchState: ObservableObject {
    @Published var theme = NotchTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .blue {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    let timeline = PlaybackTimeline()
    let volume = SystemVolume()
    var skipTrack: ((TrackSkip) -> Void)?
    var togglePlayback: (() -> Void)?
    @Published var changingPlayback = false
    @Published var skippingTrack = false
    @Published var skipMessage = ""
    var hoverWork: DispatchWorkItem?
    var pinned = false
    @Published var hoverToOpen = UserDefaults.standard.bool(forKey: "hoverToOpen") {
        didSet { hoverWork?.cancel(); UserDefaults.standard.set(hoverToOpen, forKey: "hoverToOpen") }
    }
    @Published var printActivity: PrintActivity?
    @Published var printSide: PrintIndicatorSide?
    @Published var hasPhysicalNotch = true
    @Published var rendersNotch = false
    var hasCollapsedNotch: Bool { hasPhysicalNotch || rendersNotch }
    var showsPrintActivity: Bool { printActivity != nil && printSide != nil && !expanded }
    @Published var showingAirPodsNotice = false
    @Published var airPods: AirPodsStatus?
    @Published var airPodsMessage = "Checking AirPods…"
    @Published var rightMenuFree = false
    var refreshAirPods: (() -> Void)?
    var airPodsDots: [AirPodsDot] { showsPrintActivity || !showingAirPodsNotice || airPods == nil || expanded || mergesIndicatorsIntoNotch ? [] : AirPodsLayout.dots(leftFree: !crowded, rightFree: rightMenuFree) }
    @Published var battery: BatteryStatus?
    @Published var audioOutput = "Audio output unavailable"
    @Published var connection: ConnectionEvent?
    @Published var appName = "Notch"
    @Published var frontmostBundleIdentifier: String?
    var mergesIndicatorsIntoNotch: Bool {
        MenuSpacePolicy.mergesIndicatorsIntoNotch(bundleIdentifier: frontmostBundleIdentifier)
    }
    @Published var menus: [MenuEntry] = []
    @Published var menuPlacementStatus = "Checking app-menu space…"
    @Published var trusted = false
    @Published var menuReadSucceeded = false
    @Published var menuAccessStatus = "Checking Accessibility and menu read…"
    @Published var expanded = false
    @Published var playbackStatus = "Checking system Now Playing…"
    @Published var playback: NowPlayingTrack?
    @Published var notchWidth: CGFloat = 190
    @Published var notchHeight: CGFloat = 32
    @Published var indicatorDiameter: CGFloat = 22
    @Published var compactWidth: CGFloat = 190
    @Published var crowded = true
    var dotOnRight: Bool { connection != nil || crowded }
    var showsDetachedDot: Bool {
        !showsPrintActivity && !mergesIndicatorsIntoNotch && (connection != nil || playback != nil) &&
        !(showingAirPodsNotice && airPods != nil) && !expanded &&
        MenuSpacePolicy.canShowDetachedDot(onRight: dotOnRight, rightFree: rightMenuFree)
    }
    var dotCenterX: CGFloat {
        let distance = notchWidth / 2 + 8 + 11
        return dotOnRight ? distance : -distance
    }
    var accent: Color { theme.color }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayHost: NSHostingView<NotchView> {
    var state: NotchState?
    var checkingMenuSpace = false
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !checkingMenuSpace, let state else { return nil }
        let local = convert(point, from: superview)
        let topDistance = isFlipped ? local.y : bounds.height - local.y
        if state.showsPrintActivity, let side = state.printSide,
           side.frame(centerX: bounds.midX, rowTop: 0, notchWidth: state.notchWidth,
                      rowHeight: state.notchHeight).contains(CGPoint(x: local.x, y: topDistance)) {
            return super.hitTest(point)
        }
        for dot in state.airPodsDots {
            let center = (state.notchWidth / 2 + 19) * (dot.onLeft ? -1 : 1)
            let dx = local.x - bounds.midX - center
            let dy = topDistance - state.notchHeight / 2
            if dx * dx + dy * dy <= pow(state.indicatorDiameter / 2, 2) { return super.hitTest(point) }
        }
        if state.showsDetachedDot {
            let dx = local.x - bounds.midX - state.dotCenterX
            let dy = topDistance - state.notchHeight / 2
            if dx * dx + dy * dy <= pow(state.indicatorDiameter / 2, 2) { return super.hitTest(point) }
        }
        guard state.expanded || state.hasCollapsedNotch else { return nil }
        let width: CGFloat = state.expanded ? 420 : state.compactWidth
        let height = state.notchHeight + (state.expanded ? 480 : 0)
        guard topDistance >= 0, topDistance <= height,
              abs(local.x - bounds.midX) <= width / 2 else { return nil }
        return super.hitTest(point)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let state = NotchState()
    var panel: NotchPanel!
    var status: NSStatusItem!
    var timer: Timer?
    private var printTimer: Timer?
    private var readingPrintQueue = false
    private var checkingForUpdates = false
    private var targetScreen: NSScreen?
    private var targetScreenFrame: CGRect?
    var bridge: NowPlayingMonitor?
    let airPodsMonitor = AirPodsMonitor()
    private var airPodsNotice = AirPodsConnectionNotice()
    private var airPodsNoticeExpiry: DispatchWorkItem?
    let systemStatus = SystemStatusMonitor()
    private let menuQueue = DispatchQueue(label: "notch.menu-reader")
    private var readingMenus = false
    private var menuPID: pid_t = 0
    var connectionQueue: [ConnectionEvent] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = OverlayHost(rootView: NotchView(state: state, permission: requestPermission))
        host.state = state
        panel.contentView = host
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notch")
        let menu = NSMenu()
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for theme in NotchTheme.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.representedObject = theme.rawValue
            item.target = self
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)
        menu.addItem(withTitle: "Open on Hover", action: #selector(toggleHover), keyEquivalent: "")
        menu.addItem(withTitle: "Enable Accessibility…", action: #selector(requestPermission), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Accessibility Diagnostics", action: #selector(copyAccessibilityDiagnostics), keyEquivalent: "")
        menu.addItem(withTitle: "Show / Hide Notch", action: #selector(toggleVisible), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notch", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.refresh() }
        printTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refreshPrintActivity() }
        refreshPrintActivity()
        bridge = NowPlayingMonitor { [weak self] playback in
            guard let self else { return }
            self.state.playback = playback
            self.state.timeline.update(playback)
        }
        bridge?.status = { [weak self] message in self?.state.playbackStatus = message }
        bridge?.start()
        state.timeline.seekRequested = { [weak self] position, id, completion in
            guard let self, let bridge = self.bridge else { completion(false); return }
            bridge.seek(to: position, trackID: id, completion: completion)
        }
        state.skipTrack = { [weak self] direction in
            guard let self, let track = self.state.playback, let bridge = self.bridge, !self.state.skippingTrack, !self.state.changingPlayback else { return }
            self.state.skippingTrack = true
            self.state.skipMessage = ""
            bridge.skip(direction, trackID: track.id) { [weak self] success in
                self?.state.skippingTrack = false
                if !success { self?.state.skipMessage = "This player couldn’t change tracks" }
            }
        }
        state.togglePlayback = { [weak self] in
            guard let self, let track = self.state.playback,
                  let bridge = self.bridge, !self.state.changingPlayback, !self.state.skippingTrack else { return }
            self.state.changingPlayback = true
            self.state.skipMessage = ""
            bridge.togglePlayback(trackID: track.id) { [weak self] success in
                self?.state.changingPlayback = false
                if !success { self?.state.skipMessage = "This player couldn’t change playback" }
            }
        }
        state.timeline.start()
        state.volume.start()
        systemStatus.update = { [weak self] snapshot, events in
            guard let self else { return }
            self.state.battery = snapshot.battery
            self.state.audioOutput = snapshot.audioName
            self.airPodsMonitor.outputChanged(snapshot.audioName)
            self.connectionQueue.append(contentsOf: events)
            self.advanceConnection()
        }
        airPodsMonitor.update = { [weak self] status, message, authoritative in
            guard let self else { return }
            let connected = self.airPodsNotice.update(status, authoritative: authoritative)
            if self.state.airPods != status { self.state.airPods = status }
            if connected {
                self.airPodsNoticeExpiry?.cancel()
                self.state.showingAirPodsNotice = true
                let name = status?.name ?? ""
                let expiry = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.state.showingAirPodsNotice = false
                    // The AirPods notice already represented this output switch.
                    let routeTitle = "Audio → \(name)"
                    if self.state.connection?.title == routeTitle { self.state.connection = nil }
                    self.connectionQueue.removeAll { $0.title == routeTitle }
                }
                self.airPodsNoticeExpiry = expiry
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: expiry)
            } else if authoritative && status == nil {
                self.airPodsNoticeExpiry?.cancel()
                self.state.showingAirPodsNotice = false
            }
            if self.state.airPodsMessage != message { self.state.airPodsMessage = message }
        }
        state.refreshAirPods = { [weak self] in self?.airPodsMonitor.refresh() }
        airPodsMonitor.start()
        systemStatus.start()
        refresh()
        panel.orderFrontRegardless()
    }

    @objc func selectTheme(_ item: NSMenuItem) {
        if let value = item.representedObject as? String, let theme = NotchTheme(rawValue: value) { state.theme = theme }
    }
    @objc func toggleHover() { state.hoverToOpen.toggle() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectTheme(_:)) { menuItem.state = menuItem.representedObject as? String == state.theme.rawValue ? .on : .off }
        if menuItem.action == #selector(toggleHover) { menuItem.state = state.hoverToOpen ? .on : .off }
        if menuItem.action == #selector(checkForUpdates) { return !checkingForUpdates }
        return true
    }

    @objc private func checkForUpdates() {
        guard !checkingForUpdates else { return }
        checkingForUpdates = true
        Task { @MainActor in
            defer { checkingForUpdates = false }
            let alert = NSAlert()
            var releasePage: URL?
            let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            do {
                if let release = try await ReleaseUpdate.latest() {
                    guard let newer = ReleaseUpdate.isNewer(release.version, than: installed) else {
                        throw URLError(.cannotParseResponse)
                    }
                    if newer {
                        alert.messageText = "Notch \(release.version) is available"
                        alert.informativeText = "You’re running Notch \(installed)."
                        releasePage = release.page
                    } else {
                        alert.messageText = "Notch is up to date"
                        alert.informativeText = "You’re running Notch \(installed)."
                    }
                } else {
                    alert.messageText = "No published Notch releases were found"
                }
            } catch {
                alert.messageText = "Couldn’t check for updates"
                alert.informativeText = error.localizedDescription
            }
            if let releasePage {
                alert.addButton(withTitle: "Open Release")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releasePage) }
            } else {
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func refreshPrintActivity() {
        guard !readingPrintQueue else { return }
        readingPrintQueue = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let activity = PrintActivity.readQueue()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.readingPrintQueue = false
                guard self.state.printActivity != activity else { return }
                self.state.printActivity = activity
                if activity == nil { self.state.printSide = nil }
                self.refresh()
            }
        }
    }

    func advanceConnection() {
        if let event = state.connection, event.expires > Date() { return }
        if connectionQueue.isEmpty { state.connection = nil; return }
        let next = connectionQueue.removeFirst()
        state.connection = ConnectionEvent(next.title, symbol: next.symbol, connected: next.connected)
    }

    @objc func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        state.trusted = AXIsProcessTrustedWithOptions(options)
        // The prompt is asynchronous; refresh again after returning from Settings.
        if !state.trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }
    @objc func copyAccessibilityDiagnostics() {
        let report = """
        Notch Accessibility diagnostics
        App: \(Bundle.main.bundleURL.path)
        Executable: \(Bundle.main.executableURL?.path ?? "Unknown")
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")
        PID: \(ProcessInfo.processInfo.processIdentifier)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Trust flag now: \(AXIsProcessTrusted())
        Active app: \(state.appName) (PID \(menuPID))
        \(state.menuAccessStatus)
        \(state.menuPlacementStatus)
        Menu rectangles: \(state.menus.count)
        Right dot area free: \(state.rightMenuFree)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
    @objc func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); printTimer?.invalidate(); bridge?.stop(); state.timeline.stop(); state.volume.stop(); systemStatus.stop(); airPodsMonitor.stop(); airPodsNoticeExpiry?.cancel() }
    @objc func quit() { NSApp.terminate(nil) }

    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private struct MenuReadResult {
        var entries: [MenuEntry] = []
        var error: AXError
        var geometryReadable = false
    }

    private func readMenus(pid: pid_t) -> MenuReadResult {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var rawBar: CFTypeRef?
        let barError = AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &rawBar)
        guard barError == .success else { return MenuReadResult(error: barError) }
        if let rawBar, CFGetTypeID(rawBar) == AXUIElementGetTypeID() {
            let bar = unsafeBitCast(rawBar, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(bar, 0.5)
            var rawChildren: CFTypeRef?
            let childError = AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &rawChildren)
            guard childError == .success else { return MenuReadResult(error: childError) }
            let children = rawChildren as? [AXUIElement] ?? []
            var extras: [AXUIElement] = []
            if let rawExtras = attribute(element, kAXExtrasMenuBarAttribute), CFGetTypeID(rawExtras) == AXUIElementGetTypeID() {
                extras = attribute(unsafeBitCast(rawExtras, to: AXUIElement.self), kAXChildrenAttribute) as? [AXUIElement] ?? []
            }
            var entries: [MenuEntry] = []
            for child in children + extras.filter({ extra in !children.contains { CFEqual($0, extra) } }) {
                AXUIElementSetMessagingTimeout(child, 0.2)
                // Some menu items (including symbols) have no title but still occupy space.
                let title = attribute(child, kAXTitleAttribute) as? String ?? ""
                var point = CGPoint.zero
                var size = CGSize.zero
                if let raw = attribute(child, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() { AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgPoint, &point) }
                if let raw = attribute(child, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() { AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgSize, &size) }
                let extra = extras.contains { CFEqual($0, child) } || attribute(child, kAXSubroleAttribute) as? String == "AXMenuExtra"
                entries.append(MenuEntry(title: title, frame: CGRect(origin: point, size: size), isExtra: extra))
            }
            return MenuReadResult(entries: entries, error: .success,
                                  geometryReadable: MenuSpacePolicy.hasReadableGeometry(entries))
        }
        return MenuReadResult(error: .noValue)
    }

    // AX hit testing can synchronously call our own OverlayHost.hitTest.
    // Run it on the main actor so AppKit cannot reenter views on the worker.
    @MainActor
    private func menuSpaceIsFree(_ rect: CGRect, menus: [MenuEntry], allowsUnverifiedSpace: Bool = false) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        // Check menu rectangles first because AX can return our own overlay.
        guard !MenuSpacePolicy.dotOverlapsMenu(menus, dot: rect) else { return false }
        if let statusFrame = status.button?.window?.frame, let primary = NSScreen.screens.first {
            let statusRect = CGRect(x: statusFrame.minX, y: primary.frame.maxY - statusFrame.maxY,
                                    width: statusFrame.width, height: statusFrame.height)
            if rect.intersects(statusRect) { return false }
        }
        let host = panel.contentView as? OverlayHost
        host?.checkingMenuSpace = true
        defer { host?.checkingMenuSpace = false }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        let steps = max(2, Int(ceil(rect.width / 8)))
        for step in 0...steps {
            let x = rect.minX + rect.width * CGFloat(step) / CGFloat(steps)
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(x), Float(rect.midY), &hit) == .success,
                  var current = hit else {
                if allowsUnverifiedSpace { continue }
                return false
            }
            var pid: pid_t = 0
            AXUIElementGetPid(current, &pid)
            if pid == ProcessInfo.processInfo.processIdentifier { continue }
            for _ in 0..<5 {
                let role = attribute(current, kAXRoleAttribute) as? String ?? ""
                if [kAXMenuBarItemRole, kAXMenuItemRole, kAXButtonRole, kAXCheckBoxRole, kAXPopUpButtonRole].contains(role) { return false }
                if role == kAXMenuBarRole { break }
                guard let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                current = unsafeBitCast(parent, to: AXUIElement.self)
            }
        }
        return true
    }

    private func accessDescription(_ error: AXError, geometryReadable: Bool) -> String {
        let flag = state.trusted ? "ON" : "OFF"
        switch error {
        case .success:
            return geometryReadable ? "Accessibility check: \(flag) · app-menu geometry readable" : "Accessibility check: \(flag) · menu read succeeded but positions unavailable"
        case .apiDisabled: return "Accessibility check: \(flag) · Accessibility API disabled for this process (AX \(error.rawValue))"
        case .cannotComplete: return "Accessibility check: \(flag) · app did not answer the menu read (AX \(error.rawValue))"
        case .attributeUnsupported, .noValue: return "Accessibility check: \(flag) · this app did not expose menus (AX \(error.rawValue))"
        default: return "Accessibility check: \(flag) · menu read failed (AX \(error.rawValue))"
        }
    }

    @objc func refresh() {
        advanceConnection()
        state.trusted = AXIsProcessTrusted()
        let screens = NSScreen.screens
        let openScreen = state.expanded ? screens.first { $0.frame == targetScreenFrame } : nil
        guard let screen = openScreen ?? screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? screens.first else { return }
        let hasPhysicalNotch = screen.safeAreaInsets.top > 0
        if targetScreenFrame != screen.frame {
            targetScreenFrame = screen.frame
            state.menus = []
            state.menuReadSucceeded = false
            state.rightMenuFree = false
            state.printSide = nil
            state.rendersNotch = !hasPhysicalNotch
        }
        targetScreen = screen
        state.hasPhysicalNotch = hasPhysicalNotch
        if hasPhysicalNotch && state.rendersNotch { state.rendersNotch = false }
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let notchGap = left.flatMap { leftArea in right.map { (leftArea.maxX, $0.minX) } }
        let physicalWidth = notchGap.map { $0.1 - $0.0 } ?? (state.hasPhysicalNotch ? 190 : 120)
        state.notchWidth = physicalWidth > 0 ? physicalWidth : 190
        state.notchHeight = MenuSpacePolicy.indicatorRowHeight(
            safeAreaTop: screen.safeAreaInsets.top,
            visibleTopInset: screen.frame.maxY - screen.visibleFrame.maxY,
            fallback: NSStatusBar.system.thickness)
        state.indicatorDiameter = MenuSpacePolicy.indicatorDiameter(
            rowHeight: state.notchHeight, hasNotch: screen.safeAreaInsets.top > 0)

        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            state.appName = app.localizedName ?? "Active app"
            state.frontmostBundleIdentifier = app.bundleIdentifier
            if menuPID != app.processIdentifier {
                menuPID = app.processIdentifier
                state.menus = []
                state.menuReadSucceeded = false
                state.rightMenuFree = false
                state.printSide = nil
                state.menuAccessStatus = "Accessibility check: \(state.trusted ? "ON" : "OFF") · reading \(state.appName) menus…"
            }
            // A non-prompting AX read verifies actual access even if the trust
            // check is stale. macOS still enforces the permission on this call.
            if !readingMenus {
                readingMenus = true
                let pid = app.processIdentifier
                let screenFrame = screen.frame
                let notchRight = notchGap?.1 ?? screenFrame.midX + state.notchWidth / 2
                let centerX = notchRight - state.notchWidth / 2
                let top = (NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY) - screen.frame.maxY
                let diameter = state.indicatorDiameter
                let rightDot = CGRect(x: notchRight + 19 - diameter / 2,
                                      y: top + (state.notchHeight - diameter) / 2,
                                      width: diameter, height: diameter)
                menuQueue.async { [weak self] in
                    guard let self else { return }
                    let result = self.readMenus(pid: pid)
                    DispatchQueue.main.async {
                        self.readingMenus = false
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                              self.targetScreenFrame == screenFrame else { return }
                        self.state.trusted = AXIsProcessTrusted()
                        self.state.menus = result.entries
                        self.state.menuReadSucceeded = result.error == .success && result.geometryReadable
                        let rowHeight = self.state.notchHeight
                        let width = self.state.notchWidth
                        let menuEnd = MenuSpacePolicy.menuEnd(result.entries, screen: screenFrame,
                                                              primaryTop: top + screenFrame.maxY, menuHeight: rowHeight)
                        let verified = self.state.menuReadSucceeded && menuEnd != nil
                        self.state.rightMenuFree = self.state.menuReadSucceeded &&
                            self.menuSpaceIsFree(rightDot, menus: result.entries)
                        if !self.state.hasPhysicalNotch {
                            let body = CGRect(x: centerX - width / 2, y: top, width: width, height: rowHeight)
                            // AX can expose app-menu frames only on the active display.
                            let rendersNotch = !MenuSpacePolicy.dotOverlapsMenu(result.entries, dot: body) &&
                                (!self.state.trusted ||
                                 self.menuSpaceIsFree(body, menus: result.entries, allowsUnverifiedSpace: true))
                            if self.state.rendersNotch != rendersNotch { self.state.rendersNotch = rendersNotch }
                        }
                        var printSide: PrintIndicatorSide?
                        if self.state.printActivity != nil, verified, !self.state.mergesIndicatorsIntoNotch {
                            printSide = PrintIndicatorSide.allCases.first { side in
                                let rect = side.frame(centerX: centerX, rowTop: top, notchWidth: width, rowHeight: rowHeight)
                                return rect.minX >= screenFrame.minX && rect.maxX <= screenFrame.maxX &&
                                    (side == .right || (menuEnd ?? .infinity) <= rect.minX - 4) &&
                                    self.menuSpaceIsFree(rect, menus: result.entries)
                            }
                        }
                        if self.state.printSide != printSide { self.state.printSide = printSide }
                        self.state.menuAccessStatus = self.accessDescription(result.error, geometryReadable: result.geometryReadable)
                        self.applyPlacement()
                    }
                }
            }
        }
        applyPlacement()
        let centerX = notchGap.map { ($0.0 + $0.1) / 2 } ?? screen.frame.midX

        let width: CGFloat = max(420, state.notchWidth + 100)
        let frame = NSRect(x: centerX - width / 2, y: screen.frame.maxY - state.notchHeight - 480, width: width, height: state.notchHeight + 480)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
    private func applyPlacement() {
        guard let screen = targetScreen else { return }
        let centerX = screen.auxiliaryTopLeftArea.flatMap { left in screen.auxiliaryTopRightArea.map { (left.maxX + $0.minX) / 2 } } ?? screen.frame.midX
        let notchLeft = centerX - state.notchWidth / 2
        let end = MenuSpacePolicy.menuEnd(state.menus, screen: screen.frame,
                                          primaryTop: NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY,
                                          menuHeight: state.notchHeight)
        state.crowded = MenuSpacePolicy.isCrowded(notchLeft: notchLeft, menuEnd: end,
                                                 trusted: state.trusted || state.menuReadSucceeded, wasCrowded: state.crowded)
        state.compactWidth = state.notchWidth
        if state.mergesIndicatorsIntoNotch {
            state.menuPlacementStatus = "Indicators hidden beside Numbers menus · click the notch to open"
        } else if state.dotOnRight && !state.rightMenuFree {
            state.menuPlacementStatus = "Dot hidden · right-side menu space unavailable"
        } else if !state.trusted && !state.menuReadSucceeded {
            state.menuPlacementStatus = "Right dot · app menu access has not been verified"
        } else if let end {
            let gap = Int((notchLeft - end).rounded())
            state.menuPlacementStatus = state.crowded ? "Right dot · app menus leave \(gap) pt beside the notch" : "Left dot · \(gap) pt free beside the notch"
        } else {
            state.menuPlacementStatus = "Right dot · menu positions unavailable on this display"
        }
    }

}

struct NotchView: View {
    @ObservedObject var state: NotchState
    let permission: () -> Void
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: state.notchWidth, height: state.notchHeight)
                        .contentShape(Rectangle()).onTapGesture(perform: toggleMusic)
                }
                if state.expanded {
                    if let playback = state.playback {
                        HStack(spacing: 14) {
                            artwork(playback).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(playback.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text(playback.artist).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
                                HStack(spacing: 14) {
                                    Button { state.skipTrack?(.previous) } label: {
                                        Image(systemName: "backward.end.fill").frame(width: 24, height: 22).contentShape(Rectangle())
                                    }.accessibilityLabel("Previous track").help("Previous track")
                                    Button { state.togglePlayback?() } label: {
                                        Image(systemName: playback.playing ? "pause.fill" : "play.fill").frame(width: 24, height: 22).contentShape(Rectangle())
                                    }.accessibilityLabel(playback.playing ? "Pause playback" : "Resume playback")
                                        .help(playback.playing ? "Pause playback" : "Resume playback")
                                    Button { state.skipTrack?(.next) } label: {
                                        Image(systemName: "forward.end.fill").frame(width: 24, height: 22).contentShape(Rectangle())
                                    }.accessibilityLabel("Next track").help("Next track")
                                }.buttonStyle(.plain).foregroundStyle(state.accent).disabled(state.skippingTrack || state.changingPlayback)
                            }
                            Spacer(minLength: 4)
                            MusicSpectrum(tint: state.theme.nsColor, playing: playback.playing, reduceMotion: reduceMotion)
                                .frame(width: 26, height: 20)
                                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                            Button(action: closeMenu) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                                .buttonStyle(.plain).foregroundStyle(.gray).help("Close music view")
                        }
                        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 18)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(state.appName).font(.system(size: 14, weight: .semibold))
                            Text(state.playbackStatus).font(.system(size: 11)).foregroundStyle(.gray)
                        }.padding(18)
                    }
                    StackedMusicSliders(timeline: state.timeline, volume: state.volume, accent: state.accent)
                        .padding(.horizontal, 18).padding(.bottom, 14)
                    VStack(alignment: .leading, spacing: 10) {
                        if let activity = state.printActivity {
                            HStack {
                                Label(activity.label, systemImage: "printer.fill")
                                Spacer()
                                if let progress = activity.progress {
                                    Text(progress, format: .percent.precision(.fractionLength(0)))
                                        .monospacedDigit()
                                }
                            }.foregroundStyle(state.accent)
                        }
                        if let event = state.connection {
                            Label(event.title, systemImage: event.symbol)
                                .foregroundStyle(event.connected ? .green : .orange).lineLimit(1)
                        }
                        HStack {
                            if let battery = state.battery {
                                Label("\(battery.percent)% · \(battery.description)", systemImage: battery.symbol)
                                    .foregroundStyle(battery.charging ? .green : .white)
                            } else { Label("Battery unavailable", systemImage: "battery.0").foregroundStyle(.gray) }
                            Spacer()
                        }
                        Label(state.audioOutput, systemImage: "speaker.wave.2").foregroundStyle(.gray).lineLimit(1)
                        HStack(spacing: 8) {
                            if let pods = state.airPods {
                                Label(pods.name, systemImage: pods.symbol).lineLimit(1)
                                Spacer()
                                Text(pods.details).font(.system(size: 10)).foregroundStyle(.gray)
                            } else {
                                Text(state.airPodsMessage).font(.system(size: 10)).foregroundStyle(.gray)
                                Spacer()
                            }
                            Button { state.refreshAirPods?() } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.plain).help("Refresh AirPods battery")
                        }
                        Text(state.menuAccessStatus).font(.system(size: 10)).foregroundStyle(.gray).lineLimit(2)
                        Text(state.menuPlacementStatus).font(.system(size: 10)).foregroundStyle(.gray).lineLimit(2)
                        if !state.trusted && !state.menuReadSucceeded {
                            Button("Check Accessibility access…", action: permission).buttonStyle(.plain).foregroundStyle(state.accent)
                        }
                        ThemeSwatches(selection: $state.theme)
                        Divider().overlay(.white.opacity(0.12))
                        HStack {
                            Toggle("Open on hover", isOn: $state.hoverToOpen).toggleStyle(ThemeSwitchStyle(color: state.accent)).controlSize(.mini)
                            Spacer()
                            Button("Close", action: closeMenu).buttonStyle(.plain).foregroundStyle(.gray)
                        }
                    }.font(.system(size: 11)).padding(.horizontal, 18).padding(.bottom, 16)
                }
            }
            .frame(width: state.expanded ? 420 : state.compactWidth)
            // The screen's exclusion rectangle isn't a trace of the camera's curved edge.
            // Leave it transparent when collapsed, exposing the real hardware outline.
            .background {
                UnevenNotch().fill(state.expanded || state.rendersNotch ? Color.black : Color.clear)
            }
            .tint(state.accent)
            .accentColor(state.accent)
            .foregroundStyle(.white)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: state.compactWidth)
            .onHover(perform: handleHover)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if state.showsPrintActivity, let activity = state.printActivity, let side = state.printSide {
                let rect = side.frame(centerX: 0, rowTop: 0, notchWidth: state.notchWidth, rowHeight: state.notchHeight)
                Button(action: toggleMusic) {
                    PrintIndicator(activity: activity, side: side, accent: state.accent)
                        .frame(width: rect.width, height: rect.height)
                        .background(.black, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(activity.label)
                .accessibilityValue(activity.progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Progress unavailable")
                .help(activity.label)
                .onHover(perform: handleHover)
                .offset(x: rect.midX, y: rect.minY)
            }
            ForEach(state.airPodsDots) { dot in
                if let pods = state.airPods {
                    Button(action: toggleMusic) {
                        AirPodsDotView(pods: pods, battery: dot.isBattery, accent: state.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dot.isBattery ? "\(pods.name) battery: \(pods.percent.map { "\($0) percent" } ?? "unavailable")" : pods.name)
                    .help("\(pods.name) · \(pods.details)")
                    .onHover(perform: handleHover)
                    .scaleEffect(state.indicatorDiameter / 22)
                    .offset(x: (state.notchWidth / 2 + 19) * (dot.onLeft ? -1 : 1), y: (state.notchHeight - 22) / 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
            if state.showsDetachedDot {
                Button(action: toggleMusic) {
                    Group {
                        if let event = state.connection {
                            Image(systemName: event.symbol).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(event.connected ? .green : .orange)
                        } else if let playback = state.playback {
                            artwork(playback).frame(width: 12, height: 12).clipShape(Circle())
                        }
                    }.frame(width: 22, height: 22)
                        .background(.black, in: Circle())
                        .overlay(Circle().stroke(state.accent.opacity(0.5), lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.connection?.title ?? "Show now playing")
                .help(state.connection?.title ?? "Show now playing")
                .onHover(perform: handleHover)
                .scaleEffect(state.indicatorDiameter / 22)
                .offset(x: state.dotCenterX, y: (state.notchHeight - 22) / 2)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: state.showsDetachedDot)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: state.dotCenterX)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: state.airPodsDots)
    }

    func closeMenu() { state.hoverWork?.cancel(); state.pinned = false; setExpanded(false) }

    func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { state.expanded = value }
    }

    func handleHover(_ inside: Bool) {
        state.hoverWork?.cancel()
        guard state.hoverToOpen else { return }
        let work = DispatchWorkItem {
            if inside { setExpanded(true) }
            else if !state.pinned { setExpanded(false) }
        }
        state.hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.3 : 0.45), execute: work)
    }

    func toggleMusic() {
        state.hoverWork?.cancel()
        if state.expanded && !state.pinned { state.pinned = true }
        else { state.pinned = !state.expanded; setExpanded(!state.expanded) }
    }

    func artwork(_ playback: NowPlayingTrack) -> some View {
        Group {
            if let image = playback.artwork {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.12))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel("Album artwork for \(playback.title)")
    }
}

struct AirPodsDotView: View {
    let pods: AirPodsStatus
    let battery: Bool
    let accent: Color
    var body: some View {
        ZStack {
            Circle().fill(.black)
            if battery {
                Circle().stroke(accent.opacity(0.2), lineWidth: 2).padding(2)
                if let percent = pods.percent {
                    Circle().trim(from: 0, to: CGFloat(percent) / 100)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(2)
                    Text("\(percent)").font(.system(size: 8, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                } else {
                    Text("–").font(.system(size: 10)).foregroundStyle(.gray)
                }
            } else {
                Image(systemName: pods.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
        }.frame(width: 22, height: 22).contentShape(Circle())
    }
}

private struct PrintIndicator: View {
    let activity: PrintActivity
    let side: PrintIndicatorSide
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: activity.progress != nil || reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
            let vertical = side == .right
            HStack(spacing: 4) {
                Image(systemName: "printer.fill").font(.system(size: 8))
                GeometryReader { geometry in
                    let length = vertical ? geometry.size.height : geometry.size.width
                    let fill = activity.progress ?? 0.3
                    let offset = activity.progress == nil && !reduceMotion ? phase * length * (1 - fill) : 0
                    Capsule().fill(accent.opacity(0.25))
                        .overlay(alignment: vertical ? .bottom : .leading) {
                            Capsule().fill(accent)
                                .frame(width: vertical ? nil : length * fill, height: vertical ? length * fill : nil)
                                .offset(x: vertical ? 0 : offset, y: vertical ? -offset : 0)
                        }
                }.frame(width: vertical ? 3 : 27, height: vertical ? 10 : 3)
            }
            .foregroundStyle(.white)
        }
    }
}

struct UnevenNotch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(18, rect.height / 2)
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - radius), control: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
