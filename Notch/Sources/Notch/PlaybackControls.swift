import AppKit
import SwiftUI
import Combine
import AudioToolbox
import CoreAudio

final class PlaybackTimeline: ObservableObject {
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var canSeek = false
    @Published var message = ""
    private var track: NowPlayingTrack?
    private var dragging = false
    private var dragTrackID: String?
    private var pendingSeek: (id: UUID, optimistic: NowPlayingTrack, deadline: Date)?
    var now: () -> Date = Date.init
    private var timer: Timer?
    var seekRequested: ((Double, String, @escaping (Bool) -> Void) -> Void)?

    func start() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() { timer?.invalidate(); timer = nil }

    func update(_ track: NowPlayingTrack?) {
        if self.track?.id != track?.id {
            dragging = false
            dragTrackID = nil
            pendingSeek = nil
            message = ""
        }
        if let pending = pendingSeek, let track,
           abs(track.position(at: now()) - pending.optimistic.position(at: now())) < 1 {
            pendingSeek = nil
        }
        self.track = track
        duration = track?.duration ?? 0
        canSeek = track?.canSeek ?? false
        refresh()
    }

    private func refresh() {
        guard !dragging else { return }
        let date = now()
        if let pending = pendingSeek, date < pending.deadline {
            position = pending.optimistic.position(at: date)
        } else {
            pendingSeek = nil
            position = track?.position(at: date) ?? 0
        }
    }

    func scrub(_ editing: Bool) {
        if editing {
            pendingSeek = nil
            dragging = true
            dragTrackID = track?.id
        } else {
            dragging = false
            guard let track, track.id == dragTrackID, canSeek else { refresh(); return }
            let target = min(duration, max(0, position))
            dragTrackID = nil
            // Keep stale adapter snapshots from snapping the thumb back after release.
            // A matching update confirms the seek; otherwise resume actual data after 2 s.
            let requestID = UUID()
            let date = now()
            pendingSeek = (requestID, track.atPosition(target, at: date), date.addingTimeInterval(2))
            position = target
            guard let seekRequested else { pendingSeek = nil; refresh(); return }
            seekRequested(target, track.id) { [weak self] success in
                guard let self, self.pendingSeek?.id == requestID else { return }
                if !success {
                    self.pendingSeek = nil
                    self.message = "This player couldn’t seek"
                    self.refresh()
                } else { self.message = "" }
            }
        }
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–:––" }
        let total = Int(min(seconds, 359999))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
                             : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Reads the actual default output device, including changes made by the system HUD.
final class SystemVolume: ObservableObject {
    @Published var value = 0.0
    @Published var muted = false
    @Published var canSet = false
    private var timer: Timer?
    private var device: AudioDeviceID = 0
    private var dragging = false
    private var pendingVolume: (value: Double, deadline: Date)?

    func scrub(_ editing: Bool) {
        dragging = editing
        if !editing { refresh() }
    }
    private var controls: [AudioObjectPropertyAddress] = []
    private var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    func start() {
        refresh()
        // Some drivers don't publish reliable volume notifications. A 100 ms read
        // follows hardware keys, Control Center, mute, and output-device changes.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func stop() { timer?.invalidate(); timer = nil }

    func refresh(publishVolume: Bool = true) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var current: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &current) == noErr, current != 0 else {
            canSet = false; return
        }
        if device != current {
            pendingVolume = nil
            dragging = false
        }
        device = current
        let candidates: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain)
        ]
        controls = []
        for (selector, element) in candidates {
            let candidate = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            if readControl(candidate) != nil, writable(candidate) { controls = [candidate]; break }
        }
        if controls.isEmpty {
            var pair: [UInt32] = [1, 2]
            var pairAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyPreferredChannelsForStereo, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var pairSize = UInt32(2 * MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(device, &pairAddress, 0, nil, &pairSize, &pair)
            let channels = Set(pair).sorted().map {
                AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: $0)
            }
            if channels.allSatisfy({ readControl($0) != nil && writable($0) }) { controls = channels }
        }
        let available = !controls.isEmpty
        if canSet != available { canSet = available }
        if let scalar = controls.compactMap({ readControl($0) }).max() {
            let next = min(1, max(0, Double(scalar)))
            if let pending = pendingVolume,
               abs(next - pending.value) < 0.005 || Date() >= pending.deadline {
                pendingVolume = nil
            }
            if publishVolume && !dragging && pendingVolume == nil && abs(value - next) > 0.0001 { value = next }
        }
        var mute: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        let isMuted = AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &mute) == noErr && mute != 0
        if muted != isMuted { muted = isMuted }
    }

    private func readControl(_ control: AudioObjectPropertyAddress) -> Float32? {
        var address = control
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, value.isFinite else { return nil }
        return value
    }
    private func writable(_ control: AudioObjectPropertyAddress) -> Bool {
        var address = control
        var writable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &writable) == noErr && writable.boolValue
    }

    func set(_ next: Double) {
        // Resolve the current route before writing, never a device that was unplugged.
        refresh(publishVolume: false)
        guard canSet, next.isFinite else { return }
        let scalar = Float32(min(1, max(0, next)))
        let before = controls.map { readControl($0) ?? 0 }
        let peak = before.max() ?? 0
        for (index, control) in controls.enumerated() {
            var address = control
            // Preserve the device's left/right balance when using channel controls.
            var target = controls.count > 1 && peak > 0 ? scalar * before[index] / peak : scalar
            if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &target) != noErr {
                pendingVolume = nil
                dragging = false
                refresh(); return
            }
        }
        pendingVolume = (Double(scalar), Date().addingTimeInterval(0.4))
        value = Double(scalar)
        if scalar > 0, muted {
            var mute: UInt32 = 0
            _ = AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
        }
        refresh()
    }
}

struct StackedMusicSliders: View {
    @ObservedObject var timeline: PlaybackTimeline
    @ObservedObject var volume: SystemVolume
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 4) {
                HStack {
                    Label("Track", systemImage: "music.note")
                    Spacer()
                    Text(timeline.canSeek ? "\(PlaybackTimeline.time(timeline.position)) / \(PlaybackTimeline.time(timeline.duration))" : "No timeline")
                        .monospacedDigit().foregroundStyle(.gray)
                }
                ThemedSlider(value: $timeline.position, range: 0...max(1, timeline.duration), color: accent, label: "Track position", onEditingChanged: timeline.scrub)
                    .frame(height: 18)
                    .disabled(!timeline.canSeek).accessibilityLabel("Track position")
                if !timeline.message.isEmpty { Text(timeline.message).foregroundStyle(.orange) }
            }
            VStack(spacing: 4) {
                HStack {
                    Label("Volume", systemImage: volume.muted || volume.value == 0 ? "speaker.slash" : "speaker.wave.2")
                    Spacer()
                    Text(volume.canSet ? (volume.muted ? "Muted" : "\(Int((volume.value * 100).rounded()))%") : "Use device volume")
                        .monospacedDigit().foregroundStyle(.gray)
                }
                ThemedSlider(value: Binding(get: { volume.muted ? 0 : volume.value }, set: volume.set), range: 0...1, color: accent, label: "System output volume", onEditingChanged: volume.scrub)
                    .frame(height: 18)
                    .disabled(!volume.canSet).accessibilityLabel("System output volume")
            }
        }.font(.system(size: 10)).controlSize(.small).tint(accent).accentColor(accent)
    }
}
