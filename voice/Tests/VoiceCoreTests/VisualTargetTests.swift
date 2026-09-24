import XCTest
import CoreGraphics
@testable import VoiceCore
final class VisualTargetTests: XCTestCase {
    let frame=CGRect(x:-1200,y:80,width:1000,height:800)
    func candidate(_ id: String = "settings", _ label: String = "Settings", _ x: Double = -400, _ y: Double = 150, enabled: Bool = true) -> VisualTargetPolicy.Candidate {
        .init(id:id,labels:[label],bounds:CGRect(x:x,y:y,width:100,height:50),enabled:enabled)
    }
    func testRetinaIndependentCoordinatesOnNegativeDisplayOrigin() {
        XCTAssertEqual(VisualTargetPolicy.select(point:[0.85,0.12],candidates:[candidate()],target:"the Settings button on the right",frame:frame)?.id,"settings")
    }
    func testPlausiblePointDoesNotAuthorizeMissingOrPartlyMatchingTarget() {
        XCTAssertNil(VisualTargetPolicy.select(point:[0.85,0.12],candidates:[candidate()],target:"billing settings",frame:frame))
        XCTAssertNil(VisualTargetPolicy.select(point:[0.85,0.12],candidates:[candidate("x","")],target:"settings",frame:frame))
        XCTAssertNil(VisualTargetPolicy.select(point:[0.85,0.12],candidates:[candidate()],target:"right button",frame:frame))
    }
    func testDuplicatesNeedExplicitDisambiguationAndPointAgreement() {
        let candidates=[candidate(),candidate("other","Settings",-1000,650)]
        XCTAssertNil(VisualTargetPolicy.select(point:[0.85,0.12],candidates:candidates,target:"settings",frame:frame))
        XCTAssertEqual(VisualTargetPolicy.select(point:[0.85,0.12],candidates:candidates,target:"top settings",frame:frame)?.id,"settings")
        XCTAssertNil(VisualTargetPolicy.select(point:[0.25,0.75],candidates:candidates,target:"top settings",frame:frame))
    }
    func testOverlappingDisabledOffscreenAndInvalidPredictionsReject() {
        for point in [[Double.nan,0.1],[1.1,0.1],[-0.1,0.1],[]] {
            XCTAssertNil(VisualTargetPolicy.select(point:point,candidates:[candidate()],target:"settings",frame:frame))
        }
        XCTAssertNil(VisualTargetPolicy.select(point:[0.85,0.12],candidates:[candidate(),candidate("other","Pay")],target:"settings",frame:frame))
        XCTAssertNil(VisualTargetPolicy.select(point:[0.85,0.12],candidates:[candidate(enabled:false)],target:"settings",frame:frame))
        XCTAssertTrue(VisualTargetPolicy.eligible([candidate("off","Settings",0,150)],target:"settings",frame:frame).isEmpty)
    }
    func testFreshnessRequiresSamePixelsWindowBoundsAndBoundedAge() {
        func fresh(_ now: Double = 12, _ digest: String = "same", _ window: UInt32 = 4, _ bounds: CGRect? = nil) -> Bool {
            VisualTargetPolicy.fresh(capturedAt:10,now:now,originalDigest:"same",currentDigest:digest,originalWindow:4,currentWindow:window,originalBounds:frame,currentBounds:bounds ?? frame)
        }
        XCTAssertTrue(fresh())
        XCTAssertFalse(fresh(26));XCTAssertFalse(fresh(9));XCTAssertFalse(fresh(12,"changed"))
        XCTAssertFalse(fresh(12,"same",5));XCTAssertFalse(fresh(12,"same",4,.zero))
    }
}
