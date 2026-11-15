import AppKit
import QuartzCore
import SwiftUI

/// Five theme-colored bars driven by playback state, without audio capture.
struct MusicSpectrum: NSViewRepresentable {
    let tint: NSColor
    let playing: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> SpectrumView {
        let view = SpectrumView()
        view.setColor(tint)
        view.setAnimated(playing && !reduceMotion)
        return view
    }

    func updateNSView(_ view: SpectrumView, context: Context) {
        view.setColor(tint)
        view.setAnimated(playing && !reduceMotion)
        view.setAccessibilityLabel(playing ? "Generalized playback animation" : "Music paused")
    }
}

final class SpectrumView: NSView {
    private var bars: [CALayer] = []
    private var animated = false
    private var timer: Timer?
    private var smoothed = [Float](repeating: 0, count: 5)
    private var lastFrame = ProcessInfo.processInfo.systemUptime

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Explicit layer hosting keeps AppKit/SwiftUI layout out of the bar animation.
        layer = CALayer()
        wantsLayer = true
        setAccessibilityElement(true)
        for _ in 0..<5 {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.42).cgColor
            bar.cornerRadius = 1.5
            bar.cornerCurve = .continuous
            bar.actions = ["position": NSNull(), "bounds": NSNull(), "cornerRadius": NSNull()]
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: 4)
            bar.position = CGPoint(x: bounds.midX - 10 + CGFloat(index) * 5, y: bounds.midY)
            bar.contentsScale = window?.backingScaleFactor ?? 2
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
        else if animated { start() }
    }

    func setAnimated(_ enabled: Bool) {
        guard enabled != animated else { return }
        animated = enabled
        if enabled, window != nil { start() } else { stop() }
    }

    func setColor(_ color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars { bar.backgroundColor = color.withAlphaComponent(0.65).cgColor }
        CATransaction.commit()
    }

    private func start() {
        guard timer == nil else { return }
        lastFrame = ProcessInfo.processInfo.systemUptime
        let rate = max(30, window?.screen?.maximumFramesPerSecond ?? 60)
        let timer = Timer(timeInterval: 1 / Double(rate), repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0.001, now - lastFrame))
        lastFrame = now
        let targets: [Float] = (0..<5).map { index in
            let phase = Double(index) * 1.3
            return Float(0.48 + 0.24 * sin(now * 3.1 + phase) + 0.14 * sin(now * 1.7 - phase))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let target = targets[index]
            let tau: Float = target > smoothed[index] ? 0.035 : 0.16
            smoothed[index] += (target - smoothed[index]) * (1 - exp(-Float(dt) / tau))
            let height = CGFloat(4 + 10 * smoothed[index])
            let current = bar.presentation()?.bounds.height ?? bar.bounds.height
            bar.bounds.size.height = height
            let animation = CABasicAnimation(keyPath: "bounds.size.height")
            animation.fromValue = current
            animation.toValue = height
            animation.duration = dt
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            bar.add(animation, forKey: "audio-level")
        }
        CATransaction.commit()
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        smoothed = [0, 0, 0, 0, 0]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars {
            bar.removeAllAnimations()
            bar.bounds.size.height = 4
        }
        CATransaction.commit()
    }
}
