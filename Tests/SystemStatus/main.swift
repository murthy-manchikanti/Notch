import Foundation

var old = SystemSnapshot()
old.battery = BatteryStatus(percent: 70, pluggedIn: false, charging: false)
old.audioID = 1
old.audioName = "Speakers"
var new = old
precondition(ConnectionChanges.events(from: old, to: new).isEmpty)
new.battery = BatteryStatus(percent: 71, pluggedIn: false, charging: false)
precondition(ConnectionChanges.events(from: old, to: new).isEmpty)
new.battery = BatteryStatus(percent: 71, pluggedIn: true, charging: false)
let power = ConnectionChanges.events(from: old, to: new)
precondition(power.count == 1 && power[0].connected && power[0].title == "Charger connected")
precondition(ConnectionChanges.events(from: new, to: old).first?.connected == false)
new = old; new.audioID = 2; new.audioName = "Headphones"
precondition(ConnectionChanges.events(from: old, to: new).first?.title == "Audio → Headphones")
new = old; new.displays = ["External Display"]; new.drives = ["USB Drive"]
precondition(ConnectionChanges.events(from: old, to: new).count == 2)
precondition(ConnectionChanges.events(from: new, to: old).allSatisfy { !$0.connected })
let now = Date(timeIntervalSince1970: 100)
precondition(ConnectionEvent("Test", symbol: "bolt", connected: true, now: now).expires == now.addingTimeInterval(5))
print("Passed 8 battery/connection checks")
let snapshot = SystemStatusMonitor.read()
print("Live read completed: battery \(snapshot.battery == nil ? "unavailable" : "available"), audio \(snapshot.audioID == 0 ? "unavailable" : "available")")

for (percent, expected) in [(0, "battery.0"), (12, "battery.0"),
    (13, "battery.25"), (37, "battery.25"), (38, "battery.50"),
    (62, "battery.50"), (63, "battery.75"), (87, "battery.75"),
    (88, "battery.100"), (100, "battery.100")] {
    precondition(BatteryStatus(percent: percent, pluggedIn: false, charging: false).symbol == expected)
}
precondition(BatteryStatus(percent: 100, pluggedIn: false, charging: false).description == "On battery")
precondition(BatteryStatus(percent: 100, pluggedIn: true, charging: false).symbol == "battery.100.bolt")
print("Passed 12 battery-icon regression checks")
