import AppKit

struct AirPodsStatus: Equatable {
    let name: String
    let address: String?
    let left: Int?
    let right: Int?
    let caseBattery: Int?
    let main: Int?
    var percent: Int? { [left, right].compactMap { $0 }.min() ?? main }
    var identity: String { address ?? name }
    var symbol: String {
        let lower = name.lowercased()
        return lower.contains("max") ? "airpodsmax" : lower.contains("pro") ? "airpodspro" : "airpods"
    }
    var details: String {
        var parts: [String] = []
        if let left { parts.append("L \(left)%") }
        if let right { parts.append("R \(right)%") }
        if let caseBattery { parts.append("Case \(caseBattery)%") }
        if parts.isEmpty, let main { parts.append("\(main)%") }
        return parts.isEmpty ? "Battery unavailable" : parts.joined(separator: " · ")
    }
}

enum AirPodsDecoder {
    static func percent(_ value: Any?) -> Int? {
        let number: Double?
        if let text = value as? String {
            number = Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let value = value as? NSNumber { number = value.doubleValue }
        else { number = nil }
        guard let number, number.isFinite, (0...100).contains(number) else { return nil }
        return Int(number.rounded())
    }

    static func decode(_ data: Data) -> [AirPodsStatus]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reports = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        var devices: [AirPodsStatus] = []
        func connected(_ value: Any) {
            if let entries = value as? [[String: Any]] { entries.forEach(connected); return }
            guard let entry = value as? [String: Any] else { return }
            for (name, raw) in entry {
                guard let metadata = raw as? [String: Any] else { continue }
                let model = [name, metadata["device_name"] as? String ?? "", metadata["device_minorType"] as? String ?? "", metadata["device_model"] as? String ?? ""].joined(separator: " ").lowercased()
                guard model.contains("airpods") else { continue }
                devices.append(AirPodsStatus(name: name,
                    address: metadata["device_address"] as? String,
                    left: percent(metadata["device_batteryLevelLeft"]),
                    right: percent(metadata["device_batteryLevelRight"]),
                    caseBattery: percent(metadata["device_batteryLevelCase"]),
                    main: percent(metadata["device_batteryLevelMain"])))
            }
        }
        func visit(_ value: Any) {
            if let array = value as? [Any] { array.forEach(visit) }
            if let object = value as? [String: Any] {
                for (key, child) in object {
                    if key == "device_connected" { connected(child) }
                    else if key != "device_not_connected" { visit(child) }
                }
            }
        }
        visit(reports)
        return devices
    }
}

enum AirPodsDot: String, Identifiable {
    case symbolLeft, batteryLeft, batteryRight
    var id: String { rawValue }
    var onLeft: Bool { self != .batteryRight }
    var isBattery: Bool { self != .symbolLeft }
}

enum AirPodsLayout {
    static func dots(leftFree: Bool, rightFree: Bool) -> [AirPodsDot] {
        if leftFree && rightFree { return [.symbolLeft, .batteryRight] }
        if rightFree { return [.batteryRight] }
        if leftFree { return [.batteryLeft] }
        return []
    }
}

struct AirPodsConnectionNotice {
    private var connectedID: String?
    private var expires: Date?
    mutating func update(_ status: AirPodsStatus?, authoritative: Bool, now: Date = Date()) -> Bool {
        guard authoritative else { return false }
        guard let status else { connectedID = nil; expires = nil; return false }
        guard connectedID != status.identity else { return false }
        connectedID = status.identity
        expires = now.addingTimeInterval(5)
        return true
    }
    func isVisible(at now: Date = Date()) -> Bool { expires.map { now < $0 } ?? false }
}

final class AirPodsMonitor {
    private let queue = DispatchQueue(label: "notch.airpods", qos: .utility)
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var querying = false
    private var active = false
    private var generation = UUID()
    private var outputName = ""
    private var previous: AirPodsStatus?
    var update: ((AirPodsStatus?, String, Bool) -> Void)?

    func start() {
        guard !active else { return }
        active = true
        generation = UUID()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }
    func outputChanged(_ name: String) {
        guard name != outputName else { return }
        outputName = name
        refresh()
    }
    func refresh() {
        guard active, !querying else { return }
        querying = true
        let token = generation
        queue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var devices: [AirPodsStatus]?
            do {
                try process.run()
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeout)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeout.cancel()
                if process.terminationStatus == 0 { devices = AirPodsDecoder.decode(data) }
            } catch { devices = nil }
            let result = devices
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.active else { return }
                self.querying = false
                guard let result else {
                    self.update?(self.previous, "AirPods data unavailable · Refresh to retry", false)
                    return
                }
                let selected = result.first { $0.name.localizedCaseInsensitiveCompare(self.outputName) == .orderedSame } ?? result.first
                self.previous = selected
                self.update?(selected, selected == nil ? "No connected AirPods reported" : "Battery supplied by macOS", true)
            }
        }
    }
    func stop() {
        active = false
        generation = UUID()
        querying = false
        timer?.invalidate(); timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }
}
