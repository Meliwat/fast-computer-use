import XCTest
import CoreGraphics
import CoreText
import VoiceCore
@testable import VoicePerception
final class ScreenObserverTests: XCTestCase {
    private func image(text: String? = nil, white: Bool = true) -> CGImage {
        let context=CGContext(data:nil,width:640,height:160,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray:white ? 1 : 0,alpha:1)
        context.fill(CGRect(x:0,y:0,width:640,height:160))
        if let text {
            let attributes:[NSAttributedString.Key:Any] = [NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,48,nil),NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0,alpha:1)]
            let line=CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:attributes))
            context.textPosition=CGPoint(x:30,y:60); CTLineDraw(line,context)
        }
        return context.makeImage()!
    }
    func testFingerprintsOfKnownImages() {
        let white=ScreenObserver.fingerprint(image())
        XCTAssertEqual(white.changedFraction(from:white),0)
        XCTAssertEqual(white.changedFraction(from:ScreenObserver.fingerprint(image(white:false))),1)
    }
    func testOfflineOCRFindsControlLabelAndBounds() throws {
        let regions=try ScreenObserver.recognize(image(text:"SEARCH"))
        let match=try XCTUnwrap(regions.first { $0.text.uppercased().contains("SEARCH") })
        XCTAssertGreaterThan(match.bounds.width,0)
        XCTAssertGreaterThan(match.bounds.height,0)
        XCTAssertTrue(CGRect(x:0,y:0,width:1,height:1).contains(match.bounds))
    }
    func testAccurateOCRCanNameAnUnlabeledControlWithoutDisplayAccess() async throws {
        let regions=try await ScreenObserver.textEvidence(image(text:"SEARCH"))
        let frame=CGRect(x:-640,y:80,width:640,height:160)
        let candidates=[VisualTargetPolicy.Candidate(id:"search",labels:[],bounds:frame)]
        let named=VisualTextEvidence.augment(candidates,regions:regions,frame:frame)
        XCTAssertEqual(VisualTargetPolicy.eligible(named,target:"Search",frame:frame).map(\.id),["search"])
    }
}
