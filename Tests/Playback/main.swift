import Foundation

let reference = Date(timeIntervalSince1970: 1000)
func track(_ playing: Bool = true, duration: Double = 180, elapsed: Double? = 30, rate: Double = 1, id: String = "song") -> NowPlayingTrack {
    NowPlayingTrack(title: "Song", artist: "Artist", artwork: nil, playing: playing, id: id, duration: duration, elapsed: elapsed, timestamp: reference, rate: rate)
}
precondition(track().position(at: reference.addingTimeInterval(5)) == 35)
precondition(track(false).position(at: reference.addingTimeInterval(5)) == 30)
precondition(track(rate: 2).position(at: reference.addingTimeInterval(5)) == 40)
precondition(track(elapsed: 179).position(at: reference.addingTimeInterval(10)) == 180)
precondition(!track(duration: 0).canSeek && !track(elapsed: nil).canSeek)
precondition(PlaybackTimeline.time(65) == "1:05" && PlaybackTimeline.time(3661) == "1:01:01")
let model = PlaybackTimeline()
model.update(track(false))
var seeks: [(Double, String)] = []
model.seekRequested = { value, id, completion in seeks.append((value, id)); completion(true) }
model.scrub(true)
model.position = 90
model.update(track(false, elapsed: 31))
precondition(model.position == 90 && seeks.isEmpty)
model.scrub(false)
precondition(seeks.count == 1 && seeks[0].0 == 90 && seeks[0].1 == "song")
model.scrub(true); model.position = 50
model.update(track(false, id: "new song")); model.scrub(false)
precondition(seeks.count == 1, "Track changes must cancel the drag's seek")
let volume = SystemVolume()
volume.refresh()
precondition(volume.value.isFinite && (0...1).contains(volume.value))
print("Passed 10 playback/volume checks; device volume control \(volume.canSet ? "available" : "unavailable in this environment")")

// Delayed adapter snapshots must not undo a seek, and late command failures
// must not overwrite a newer edit or a newly selected track.
var clock = reference
let seeking = PlaybackTimeline()
seeking.now = { clock }
seeking.update(track(false))
var completions: [(Bool) -> Void] = []
seeking.seekRequested = { _, _, completion in completions.append(completion) }
func seek(_ value: Double) {
    seeking.scrub(true); seeking.position = value; seeking.scrub(false)
}
seek(90)
seeking.update(track(false, elapsed: 31))
precondition(seeking.position == 90, "Stale metadata must not snap back a released seek")
completions[0](true)
seeking.update(track(false, elapsed: 32))
precondition(seeking.position == 90, "Command exit alone is not a fresh timeline")
seeking.update(track(false, elapsed: 90))
precondition(seeking.position == 90)
seeking.update(track(false, elapsed: 91))
precondition(seeking.position == 91, "Confirmed seeks must resume normal updates")
seek(120)
clock = reference.addingTimeInterval(3)
seeking.update(track(false, elapsed: 33))
precondition(seeking.position == 33, "Unconfirmed seeks must eventually follow the actual player")
seek(70)
seek(100)
completions[2](false)
precondition(seeking.position == 100 && seeking.message.isEmpty, "Old failure must not cancel a newer seek")
completions[3](false)
precondition(seeking.position == 33 && !seeking.message.isEmpty)
seek(80)
seeking.update(track(false, elapsed: 5, id: "replacement"))
completions[4](false)
precondition(seeking.position == 5 && seeking.message.isEmpty)
print("Passed 8 seek-feedback regression checks")
