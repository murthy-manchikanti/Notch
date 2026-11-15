import AppKit
import SwiftUI

/// Uses native slider tracking, keyboard and accessibility behavior, with explicit
/// track/thumb drawing so macOS can't substitute its global accent color.
struct ThemedSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    let label: String
    var onEditingChanged: (Bool) -> Void = { _ in }
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ThemeSliderControl {
        let slider = ThemeSliderControl()
        slider.cell = ThemeSliderCell()
        slider.isVertical = false
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.trackingChanged = { [weak coordinator = context.coordinator, weak slider] editing in
            guard let coordinator, let slider else { return }
            // Commit the final native value before ending the edit session.
            if !editing { coordinator.parent.value = slider.doubleValue }
            coordinator.parent.onEditingChanged(editing)
        }
        return slider
    }
    func updateNSView(_ slider: ThemeSliderControl, context: Context) {
        context.coordinator.parent = self
        // Reassigning native bounds while AppKit tracks can move the thumb.
        if slider.minValue != range.lowerBound { slider.minValue = range.lowerBound }
        if slider.maxValue != range.upperBound { slider.maxValue = range.upperBound }
        if !slider.tracking, value.isFinite, slider.doubleValue != value { slider.doubleValue = value }
        if slider.isEnabled != isEnabled { slider.isEnabled = isEnabled }
        slider.setAccessibilityLabel(label)
        (slider.cell as? ThemeSliderCell)?.themeColor = NSColor(color)
        slider.needsDisplay = true
    }
    final class Coordinator: NSObject {
        var parent: ThemedSlider
        init(_ parent: ThemedSlider) { self.parent = parent }
        @objc func changed(_ slider: ThemeSliderControl) {
            // Keyboard/accessibility changes may send actions outside mouse tracking.
            let next = slider.doubleValue
            if !slider.tracking { parent.onEditingChanged(true) }
            parent.value = next
            if !slider.tracking { parent.onEditingChanged(false) }
        }
    }
}

final class ThemeSliderControl: NSSlider {
    var tracking = false
    var trackingChanged: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        tracking = true
        trackingChanged?(true)
        super.mouseDown(with: event)
        trackingChanged?(false)
        tracking = false
    }
}

final class ThemeSliderCell: NSSliderCell {
    var themeColor = NSColor.systemBlue
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        NSColor.white.withAlphaComponent(isEnabled ? 0.18 : 0.08).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        // Use AppKit's actual thumb location so fill and native tracking agree.
        let thumbX = knobRect(flipped: flipped).midX
        let active = NSRect(x: track.minX, y: track.minY,
                            width: min(track.width, max(0, thumbX - track.minX)), height: track.height)
        themeColor.withAlphaComponent(isEnabled ? 1 : 0.2).setFill()
        NSBezierPath(roundedRect: active, xRadius: 2, yRadius: 2).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        let knob = NSRect(x: knobRect.midX - 5, y: knobRect.midY - 5, width: 10, height: 10)
        (isEnabled ? themeColor : NSColor.darkGray).setFill()
        NSBezierPath(ovalIn: knob).fill()
    }
}
