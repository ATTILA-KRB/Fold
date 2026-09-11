import CoreGraphics
import Foundation
import ImageIO

// Guards the rendered frames of `Fold --render-proof`: the desktop must fold,
// and it must never fold into flat black. Both failures are silent in a build —
// the shader compiles and every existing check passes — so they need pixels.
//
//   swift scripts/verify-frames.swift verification/frames [maxBlack%] [minMotion%]
//
// Fails when any frame is darker than maxBlack% (default 0.1) or when the most
// folded frame differs from the first one by less than minMotion% (default 5,
// which catches "the effect stopped being applied at all").
let args = Array(CommandLine.arguments.dropFirst())
guard let dir = args.first else {
    FileHandle.standardError.write("usage: verify-frames.swift <dir> [maxBlack%] [minMotion%]\n".data(using: .utf8)!)
    exit(2)
}
let maxBlack = args.count > 1 ? Double(args[1]) ?? 0.1 : 0.1
let minMotion = args.count > 2 ? Double(args[2]) ?? 5.0 : 5.0

let files = try FileManager.default.contentsOfDirectory(atPath: dir)
    .filter { $0.hasSuffix(".png") }.sorted()
guard !files.isEmpty else {
    FileHandle.standardError.write("no PNG frames in \(dir)\n".data(using: .utf8)!)
    exit(2)
}

/// Near-black means every channel under 16: the flat output of `color*coverage`.
func pixels(_ path: String) -> (w: Int, h: Int, px: [UInt8])? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard
        let ctx = CGContext(
            data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, px)
}

/// Percentage of flat-black pixels. Percent, not a fraction: the threshold is
/// compared against this value, and mixing the two units silently raised the
/// limit from 0.1% to 10%.
func blackPercent(_ frame: (w: Int, h: Int, px: [UInt8])) -> Double {
    var black = 0
    let px = frame.px
    for i in stride(from: 0, to: px.count, by: 4) {
        if max(px[i], max(px[i + 1], px[i + 2])) < 16 { black += 1 }
    }
    return 100 * Double(black) / Double(frame.w * frame.h)
}

/// Fraction of sampled pixels that differ from the reference frame.
func motion(_ a: (w: Int, h: Int, px: [UInt8]), _ b: (w: Int, h: Int, px: [UInt8])) -> Double {
    guard a.w == b.w, a.h == b.h else { return 100 }
    var moved = 0, sampled = 0
    for y in stride(from: 0, to: a.h, by: 2) {
        for x in stride(from: 0, to: a.w, by: 2) {
            let i = (y * a.w + x) * 4
            sampled += 1
            if abs(Int(a.px[i]) - Int(b.px[i])) > 12
                || abs(Int(a.px[i + 1]) - Int(b.px[i + 1])) > 12
                || abs(Int(a.px[i + 2]) - Int(b.px[i + 2])) > 12 { moved += 1 }
        }
    }
    return 100 * Double(moved) / Double(max(sampled, 1))
}

guard let first = pixels("\(dir)/\(files[0])") else { exit(2) }
var worstBlack = 0.0
var worstBlackFrame = files[0]
var bestMotion = 0.0
var bestMotionFrame = files[0]

for name in files {
    guard let frame = pixels("\(dir)/\(name)") else { continue }
    let black = blackPercent(frame)
    if black > worstBlack { worstBlack = black; worstBlackFrame = name }
    let moved = motion(first, frame)
    if moved > bestMotion { bestMotion = moved; bestMotionFrame = name }
}

print(String(format: "  frames=%d  worst black=%.3f%% (%@)  max motion=%.1f%% (%@)",
             files.count, worstBlack, worstBlackFrame, bestMotion, bestMotionFrame))

var failed = false
if worstBlack > maxBlack {
    print(String(format: "  FAIL %@ is %.3f%% flat black (limit %.3f%%) — the shader folds into black",
                 worstBlackFrame, worstBlack, maxBlack))
    failed = true
} else {
    print(String(format: "  ok   no frame exceeds %.3f%% flat black", maxBlack))
}
if bestMotion < minMotion {
    print(String(format: "  FAIL the fold barely changes the pixels (%.1f%% moved, expected %.1f%%) — is the effect applied?",
                 bestMotion, minMotion))
    failed = true
} else {
    print(String(format: "  ok   the fold moves pixels (up to %.1f%%, floor %.1f%%)", bestMotion, minMotion))
}
exit(failed ? 1 : 0)
