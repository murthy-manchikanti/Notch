import AppKit
import SwiftUI

// A keyboard/accessibility action must capture the native value before an
// editing callback can refresh the control from an older model value.
let slider = ThemeSliderControl(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
slider.minValue = 0; slider.maxValue = 1
var value = 0.2
var edits: [Bool] = []
let binding = Binding<Double>(get: { value }, set: { value = $0 })
let parent = ThemedSlider(value: binding, range: 0...1, color: .pink, label: "Test") { editing in
    edits.append(editing)
    if editing { slider.doubleValue = 0.2 }
}
let coordinator = ThemedSlider.Coordinator(parent)
slider.doubleValue = 0.8
coordinator.changed(slider)
precondition(value == 0.8 && edits == [true, false])
slider.tracking = true
edits = []
slider.doubleValue = 0.6
coordinator.changed(slider)
precondition(value == 0.6 && edits.isEmpty, "Dragging must use the existing edit session")

// Render the custom thumb in every theme and verify the actual pixel color.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
let cell = ThemeSliderCell()
cell.isEnabled = true
for theme in NotchTheme.allCases {
    cell.themeColor = theme.nsColor
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    cell.drawKnob(NSRect(x: 7, y: 7, width: 10, height: 10))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let pixel = bitmap.colorAt(x: 12, y: 12)!.usingColorSpace(.sRGB)!
    let expected = theme.nsColor.usingColorSpace(.sRGB)!
    precondition(abs(pixel.redComponent - expected.redComponent) < 0.025)
    precondition(abs(pixel.greenComponent - expected.greenComponent) < 0.025)
    precondition(abs(pixel.blueComponent - expected.blueComponent) < 0.025)
}
print("Passed 2 native-slider action and 6 theme-rendering checks")
