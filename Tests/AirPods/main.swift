import Foundation

func decode(_ connected: [[String: Any]], disconnected: [[String: Any]] = []) -> [AirPodsStatus]? {
    let root: [String: Any] = ["SPBluetoothDataType": [["device_connected": connected, "device_not_connected": disconnected]]]
    return AirPodsDecoder.decode(try! JSONSerialization.data(withJSONObject: root))
}
let sample: [String: Any] = ["My AirPods Pro": ["device_batteryLevelLeft":"80%", "device_batteryLevelRight":"82%", "device_batteryLevelCase":"45%"]]
let pods = decode([sample])!.first!
precondition(pods.percent == 80 && pods.left == 80 && pods.right == 82 && pods.caseBattery == 45)
precondition(pods.symbol == "airpodspro")
precondition(decode([], disconnected: [sample])!.isEmpty)
precondition(decode([["Keyboard": ["device_batteryLevelMain":"90%"]]])!.isEmpty)
precondition(decode([["AirPods": [:]]])!.first!.percent == nil)
precondition(AirPodsDecoder.percent("0%") == 0 && AirPodsDecoder.percent("100%") == 100)
precondition(AirPodsDecoder.percent("255%") == nil && AirPodsDecoder.percent("unknown") == nil && AirPodsDecoder.percent(-1) == nil)
precondition(AirPodsDecoder.decode(Data("bad".utf8)) == nil)
precondition(decode([["AirPods Max": ["device_batteryLevelMain":60]]])!.first?.percent == 60)
precondition(AirPodsLayout.dots(leftFree: true, rightFree: true) == [.symbolLeft, .batteryRight])
precondition(AirPodsLayout.dots(leftFree: false, rightFree: true) == [.batteryRight])
precondition(AirPodsLayout.dots(leftFree: true, rightFree: false) == [.batteryLeft])
precondition(AirPodsLayout.dots(leftFree: false, rightFree: false).isEmpty)
print("Passed 13 AirPods battery and dot-layout checks")
if CommandLine.arguments.count > 1 {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let live = AirPodsDecoder.decode(data)
    print("Live snapshot: \(live?.count ?? 0) connected AirPods; reported earbud battery \(live?.first?.percent.map(String.init) ?? "unavailable")%")
}

let start = Date(timeIntervalSince1970: 1000)
var notice = AirPodsConnectionNotice()
precondition(notice.update(pods, authoritative: true, now: start))
precondition(notice.isVisible(at: start.addingTimeInterval(4.9)))
precondition(!notice.isVisible(at: start.addingTimeInterval(5)))
precondition(!notice.update(pods, authoritative: true, now: start.addingTimeInterval(10)))
precondition(!notice.isVisible(at: start.addingTimeInterval(10)), "Battery refresh must not restart the notice")
precondition(!notice.update(nil, authoritative: false, now: start.addingTimeInterval(11)))
precondition(!notice.update(pods, authoritative: true, now: start.addingTimeInterval(12)), "Metadata failure must not invent a reconnect")
precondition(!notice.update(nil, authoritative: true, now: start.addingTimeInterval(13)))
precondition(notice.update(pods, authoritative: true, now: start.addingTimeInterval(14)))
precondition(notice.isVisible(at: start.addingTimeInterval(18)))
print("Passed 10 temporary AirPods connection-notice checks")
