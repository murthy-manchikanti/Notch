import Foundation
import AppKit

func decode(_ text: String) -> NowPlayingTrack? { NowPlayingDecoder.decode(Data(text.utf8)) }
precondition(decode("not json") == nil)
precondition(decode(#"{"type":"data","diff":false,"payload":{}}"#) == nil)
precondition(decode(#"{"type":"data","diff":true,"payload":{"title":"A","playing":true}}"#) == nil)
precondition(decode(#"{"type":"data","diff":false,"payload":{"title":"A","playing":false}}"#)?.playing == false)
precondition(decode(#"{"type":"data","diff":false,"payload":{"title":"","playing":true}}"#) == nil)
let track = decode(#"{"type":"data","diff":false,"payload":{"title":"A","artist":"B","playing":true,"artworkData":"invalid"}}"#)
precondition(track?.title == "A" && track?.artist == "B" && track?.artwork == nil)
let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let png = image.representation(using: .png, properties: [:])!.base64EncodedString()
let envelope: [String: Any] = ["type": "data", "diff": false, "payload": ["title":"Artwork", "playing": true, "artworkData":png]]
let artwork = NowPlayingDecoder.decode(try! JSONSerialization.data(withJSONObject: envelope))?.artwork
precondition(artwork != nil && artwork!.size.width <= 128 && artwork!.size.height <= 128)
print("Passed 7 Now Playing decode/artwork checks")

for (width, height) in [(320, 180), (180, 320), (180, 180)] {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let side = min(width, height)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side))
    let square = NowPlayingDecoder.squareArtwork(context.makeImage()!)!
    precondition(square.width == square.height && square.width <= 128)
    let pixels = NSBitmapImageRep(cgImage: square)
    let corner = pixels.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
    precondition(corner.blueComponent > 0.95 && corner.redComponent < 0.05, "Side background must be removed")
}
print("Passed 6 square-artwork checks: landscape, portrait, square, and background removal")
