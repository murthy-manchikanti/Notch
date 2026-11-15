import AppKit
import CoreAudio
import IOKit.ps

struct BatteryStatus: Equatable {
    let percent: Int
    let pluggedIn: Bool
    let charging: Bool
    var symbol: String {
        if pluggedIn { return "battery.100.bolt" }
        // SF Symbols provides quarter-charge levels; use the closest level.
        switch percent {
        case ...12: return "battery.0"
        case 13...37: return "battery.25"
        case 38...62: return "battery.50"
        case 63...87: return "battery.75"
        default: return "battery.100"
        }
    }
    var description: String { charging ? "Charging" : (pluggedIn ? "Power connected" : "On battery") }
}

struct ConnectionEvent: Equatable {
    let title: String
    let symbol: String
    let connected: Bool
    let expires: Date
    init(_ title: String, symbol: String, connected: Bool, now: Date = Date()) {
        self.title = title; self.symbol = symbol; self.connected = connected
        self.expires = now.addingTimeInterval(5)
    }
}

struct SystemSnapshot {
    var battery: BatteryStatus?
    var audioID: AudioDeviceID = 0
    var audioName = "Audio output unavailable"
    var displays: Set<String> = []
    var drives: Set<String> = []
}

enum ConnectionChanges {
    static func events(from old: SystemSnapshot, to new: SystemSnapshot, now: Date = Date()) -> [ConnectionEvent] {
        var events: [ConnectionEvent] = []
        if let before = old.battery, let after = new.battery, before.pluggedIn != after.pluggedIn {
            events.append(ConnectionEvent(after.pluggedIn ? "Charger connected" : "Charger disconnected", symbol: after.pluggedIn ? "bolt.fill" : "powerplug", connected: after.pluggedIn, now: now))
        }
        if new.audioID != old.audioID, new.audioID != 0 {
            events.append(ConnectionEvent("Audio → \(new.audioName)", symbol: "headphones", connected: true, now: now))
        }
        for name in new.displays.subtracting(old.displays).sorted() { events.append(ConnectionEvent("\(name) connected", symbol: "display", connected: true, now: now)) }
        for name in old.displays.subtracting(new.displays).sorted() { events.append(ConnectionEvent("\(name) disconnected", symbol: "display", connected: false, now: now)) }
        for name in new.drives.subtracting(old.drives).sorted() { events.append(ConnectionEvent("\(name) mounted", symbol: "externaldrive.fill", connected: true, now: now)) }
        for name in old.drives.subtracting(new.drives).sorted() { events.append(ConnectionEvent("\(name) ejected", symbol: "externaldrive", connected: false, now: now)) }
        return events
    }
}

final class SystemStatusMonitor {
    private var timer: Timer?
    private var previous: SystemSnapshot?
    var update: ((SystemSnapshot, [ConnectionEvent]) -> Void)?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func poll() {
        let snapshot = Self.read()
        let events = previous.map { ConnectionChanges.events(from: $0, to: snapshot) } ?? []
        previous = snapshot
        update?(snapshot, events)
    }

    static func read() -> SystemSnapshot {
        var result = SystemSnapshot()
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = description[kIOPSCurrentCapacityKey] as? Int,
                      let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
                result.battery = BatteryStatus(percent: min(100, Swift.max(0, Int((Double(current) / Double(max) * 100).rounded()))),
                                               pluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                                               charging: description[kIOPSIsChargingKey] as? Bool ?? false)
                break
            }
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 {
            result.audioID = device
            address.mSelector = kAudioObjectPropertyName
            var name: Unmanaged<CFString>?
            size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name {
                result.audioName = name.takeRetainedValue() as String
            }
        }
        result.displays = Set(NSScreen.screens.filter { $0.safeAreaInsets.top == 0 }.map(\.localizedName))
        let keys: Set<URLResourceKey> = [.volumeIsInternalKey, .volumeIsLocalKey, .volumeNameKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        result.drives = Set(volumes.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsInternal == false, values.volumeIsLocal == true else { return nil }
            return values.volumeName ?? url.lastPathComponent
        })
        return result
    }
}
