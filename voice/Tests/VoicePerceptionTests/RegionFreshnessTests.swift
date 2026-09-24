import XCTest
import CoreGraphics
@testable import VoicePerception

final class RegionFreshnessTests: XCTestCase {
    let frame = CGRect(x: -200, y: 80, width: 200, height: 120)
    let target = CGRect(x: -160, y: 110, width: 40, height: 30)
    func image(width: Int = 400, height: Int = 240, change: (Int, Int)? = nil) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        if let (x,y) = change { bytes[(y * width + x) * 4] = 0 }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    func testUnrelatedPixelsCanChangeAtRetinaScaleAndNegativeScreenOrigin() {
        XCTAssertTrue(ScreenObserver.unchangedRegion(target, frame: frame, before: image(), after: image(change: (300,200))))
    }
    func testTargetAndSurroundingPixelsMustRemainExact() {
        XCTAssertFalse(ScreenObserver.unchangedRegion(target, frame: frame, before: image(), after: image(change: (100,80))))
        XCTAssertFalse(ScreenObserver.unchangedRegion(target, frame: frame, before: image(), after: image(change: (64,40))))
    }
    func testInvalidGeometryAndChangedCaptureScaleReject() {
        XCTAssertFalse(ScreenObserver.unchangedRegion(target, frame: frame, before: image(), after: image(width: 402)))
        XCTAssertFalse(ScreenObserver.unchangedRegion(.zero, frame: frame, before: image(), after: image()))
        XCTAssertFalse(ScreenObserver.unchangedRegion(CGRect(x: -240, y: 110, width: 80, height: 30), frame: frame, before: image(), after: image()))
        XCTAssertFalse(ScreenObserver.unchangedRegion(target, frame: .zero, before: image(), after: image()))
        XCTAssertFalse(ScreenObserver.unchangedRegion(target, frame: frame, before: image(), after: image(), padding: -.infinity))
    }
    func testPaddingClipsAtFrameBoundaryButTargetMustBeFullyVisible() {
        let edge = CGRect(x: -200, y: 80, width: 30, height: 20)
        XCTAssertTrue(ScreenObserver.unchangedRegion(edge, frame: frame, before: image(), after: image(change: (300,200))))
        XCTAssertFalse(ScreenObserver.unchangedRegion(edge, frame: frame, before: image(), after: image(change: (1,1))))
    }
}
