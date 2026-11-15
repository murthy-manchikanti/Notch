import AppKit
import ImageIO

enum TrackSkip: Int {
    case next = 4
    case previous = 5
}

struct NowPlayingTrack {
    let title: String
    let artist: String
    let artwork: NSImage?
    let playing: Bool
    let id: String
    let duration: Double
    let elapsed: Double?
    let timestamp: Date
    let rate: Double
    var canSeek: Bool { duration.isFinite && duration > 0 && elapsed != nil }
    func position(at now: Date) -> Double {
        guard let elapsed else { return 0 }
        let advanced = elapsed + (playing ? max(0, now.timeIntervalSince(timestamp)) * rate : 0)
        return min(max(0, duration), max(0, advanced))
    }
    func atPosition(_ position: Double, at date: Date = Date()) -> NowPlayingTrack {
        NowPlayingTrack(title: title, artist: artist, artwork: artwork, playing: playing, id: id,
                        duration: duration, elapsed: position, timestamp: date, rate: rate)
    }
}

enum NowPlayingDecoder {
    /// Crop the central artwork square before it reaches SwiftUI, so wide video
    /// thumbnails and their side backgrounds cannot change the artwork's layout.
    static func squareArtwork(_ image: CGImage) -> CGImage? {
        let side = min(image.width, image.height)
        guard side > 0, let cropped = image.cropping(to: CGRect(
            x: (image.width - side) / 2, y: (image.height - side) / 2,
            width: side, height: side)) else { return nil }
        let outputSide = min(128, side)
        guard let context = CGContext(data: nil, width: outputSide, height: outputSide,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
        return context.makeImage()
    }

    static func decode(_ data: Data) -> NowPlayingTrack? {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["type"] as? String == "data",
              envelope["diff"] as? Bool == false,
              let payload = envelope["payload"] as? [String: Any],
              let playing = payload["playing"] as? Bool,
              let title = payload["title"] as? String, !title.isEmpty else { return nil }
        var image: NSImage?
        if let base64 = payload["artworkData"] as? String,
           let bytes = Data(base64Encoded: base64),
           let source = CGImageSourceCreateWithData(bytes as CFData, nil),
           let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceThumbnailMaxPixelSize: 256,
               kCGImageSourceCreateThumbnailWithTransform: true
           ] as CFDictionary), let square = squareArtwork(thumbnail) {
            image = NSImage(cgImage: square, size: .zero)
        }
        let duration = (payload["duration"] as? Double).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        let elapsed = (payload["elapsedTime"] as? Double).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let timestamp = (payload["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let rate = (payload["playbackRate"] as? Double).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? (playing ? 1 : 0)
        let id = [payload["bundleIdentifier"] as? String ?? "", payload["uniqueIdentifier"] as? String ?? payload["contentItemIdentifier"] as? String ?? "", title, payload["artist"] as? String ?? ""].joined(separator: "|")
        return NowPlayingTrack(title: title, artist: payload["artist"] as? String ?? "Now playing", artwork: image, playing: playing,
                               id: id, duration: duration, elapsed: elapsed, timestamp: timestamp, rate: rate)
    }
}

/// Reads macOS Now Playing using a bundled, source-built MediaRemote adapter.
/// No Apple Events, browser scripting, network listener, or browser extension.
final class NowPlayingMonitor {
    private let queue = DispatchQueue(label: "notch.now-playing")
    private var process: Process?
    private var currentTrack: NowPlayingTrack?
    private var commands: [Process] = []
    private var output: Pipe?
    private var buffer = Data()
    private let update: (NowPlayingTrack?) -> Void
    var status: ((String) -> Void)?

    init(update: @escaping (NowPlayingTrack?) -> Void) { self.update = update }

    func start() {
        guard process == nil,
              let resources = Bundle.main.resourceURL else { return }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl")
        let framework = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path), FileManager.default.fileExists(atPath: framework.path) else {
            publish(nil, "Now Playing helper missing — rebuild Notch.app")
            return
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path, "stream", "--no-diff", "--debounce=100"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.queue.async { [weak self] in self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            self?.publish(nil, "System Now Playing unavailable — restart Notch to retry")
        }
        self.process = process
        self.output = pipe
        do {
            try process.run()
            publish(nil, "Waiting for system Now Playing")
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            publish(nil, "Unable to start system Now Playing")
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        // Bound memory even if a helper emits malformed or unexpectedly large data.
        guard buffer.count <= 16 * 1024 * 1024 else {
            buffer.removeAll()
            return
        }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            let track = NowPlayingDecoder.decode(line)
            publish(track, track == nil ? "No media playing" : (track!.playing ? "System Now Playing" : "Playback paused"))
        }
    }

    private func publish(_ track: NowPlayingTrack?, _ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.currentTrack = track
            self?.update(track)
            self?.status?(message)
        }
    }

    func seek(to seconds: Double, trackID: String, completion: @escaping (Bool) -> Void) {
        guard let track = currentTrack, track.id == trackID, track.canSeek, seconds.isFinite else {
            completion(false); return
        }
        let micros = Int64(min(9_000_000_000_000, min(track.duration, max(0, seconds))) * 1_000_000)
        runCommand(["seek", String(micros)], completion: completion)
    }

    func skip(_ direction: TrackSkip, trackID: String, completion: @escaping (Bool) -> Void) {
        guard currentTrack?.id == trackID else { completion(false); return }
        runCommand(["send", String(direction.rawValue)], completion: completion)
    }

    func togglePlayback(trackID: String, completion: @escaping (Bool) -> Void) {
        guard let track = currentTrack, track.id == trackID else {
            completion(false); return
        }
        // Choose an explicit command from the latest player state.
        // kMRAPlay = 0 and kMRAPause = 1 in MediaRemoteAdapter.h.
        runCommand(["send", track.playing ? "1" : "0"], completion: completion)
    }

    private func runCommand(_ arguments: [String], completion: @escaping (Bool) -> Void) {
        guard let resources = Bundle.main.resourceURL else { completion(false); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [resources.appendingPathComponent("mediaremote-adapter.pl").path,
                             Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/MediaRemoteAdapter.framework").path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                self?.commands.removeAll { $0 === finished }
                completion(finished.terminationStatus == 0)
            }
        }
        do {
            try process.run()
            commands.append(process)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if process.isRunning { process.terminate() }
            }
        } catch { completion(false) }
    }

    func stop() {
        for command in commands where command.isRunning { command.terminate() }
        commands.removeAll()
        output?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }

    deinit { stop() }
}
