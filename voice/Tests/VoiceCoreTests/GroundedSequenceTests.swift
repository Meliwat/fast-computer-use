import XCTest
@testable import VoiceCore

final class GroundedSequenceTests: XCTestCase {
    func testExplicitThenOnlyAndBoundedLength() throws {
        XCTAssertNil(try GroundedSequence.clauses("Show Research and Development"))
        XCTAssertEqual(try GroundedSequence.clauses("Show Tools, and then open Playground."), ["Show Tools", "open Playground"])
        XCTAssertThrowsError(try GroundedSequence.clauses("Show A then show B then show C then show D"))
        XCTAssertThrowsError(try GroundedSequence.clauses("Show Tools then"))
    }
    func testPreflightReplyRequiresCorrelationCountAndSupportedConfidentOperations() throws {
        func reply(_ id:String="r",_ operation:String="activate",_ confidence:Double=0.999) throws -> GroundedPreflight {
            let json="{\"id\":\"\(id)\",\"operations\":[{\"operation\":\"activate\",\"confidence\":0.999},{\"operation\":\"\(operation)\",\"confidence\":\(confidence)}]}"
            return try JSONDecoder().decode(GroundedPreflight.self,from:Data(json.utf8))
        }
        XCTAssertTrue(try reply().accepts(requestID:"r",count:2))
        XCTAssertFalse(try reply("stale").accepts(requestID:"r",count:2))
        XCTAssertFalse(try reply().accepts(requestID:"r",count:3))
        XCTAssertFalse(try reply("r","abstain").accepts(requestID:"r",count:2))
        XCTAssertFalse(try reply("r","activate",0.98).accepts(requestID:"r",count:2))
    }
    @MainActor func testPreflightFailureSendsNoActions() async {
        var sent:[String]=[]
        do {
            _ = try await GroundedSequence.run(["Show Tools","Delete Account"], preflight:{_ in false}, stillValid:{true}, step:{text in sent.append(text);return true})
            XCTFail("must reject")
        } catch { XCTAssertTrue(sent.isEmpty) }
    }
    @MainActor func testSecondStepReadsStateAfterFirstVerification() async throws {
        var visible="Tools", seen:[String]=[]
        let count=try await GroundedSequence.run(["Show Tools","Open Playground"],preflight:{_ in true},stillValid:{true},step:{ text in
            seen.append(visible)
            if text=="Show Tools" { visible="Playground" }
            return true
        })
        XCTAssertEqual(count,2);XCTAssertEqual(seen,["Tools","Playground"])
    }
    @MainActor func testUnverifiedActionStopsWithoutReplay() async {
        var sent=0
        do {
            _ = try await GroundedSequence.run(["Show Tools","Open Playground"],preflight:{_ in true},stillValid:{true},step:{_ in sent+=1;return false})
            XCTFail("must stop")
        } catch { XCTAssertEqual(sent,1);XCTAssertTrue(error.localizedDescription.contains("step 1")) }
    }
    @MainActor func testCancellationBetweenSteps() async {
        var valid=true, sent=0
        do {
            _ = try await GroundedSequence.run(["Show Tools","Open Playground"],preflight:{_ in true},stillValid:{valid},step:{_ in sent+=1;valid=false;return true})
            XCTFail("must stop")
        } catch { XCTAssertEqual(sent,1) }
    }
}
