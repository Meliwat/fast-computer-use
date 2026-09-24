import XCTest
@testable import VoiceCore
final class GroundedTextTests:XCTestCase {
    func testLiteralTailKeepsPunctuationAndActionWords() throws {
        let clauses=try XCTUnwrap(GroundedSequence.clauses("Focus Message then type Hello, then delete Account!"))
        XCTAssertEqual(clauses,["Focus Message","type Hello, then delete Account!"])
        let plan=try GroundedSequence.preflightPlan(clauses)
        XCTAssertEqual(plan.texts,["Focus Message"])
        XCTAssertEqual(plan.requiredOperations,["focus"])
        XCTAssertEqual(try GroundedSequence.textCommand(clauses[1])?.value,"Hello, then delete Account!")
        XCTAssertNil(try GroundedSequence.clauses("type hello then open Notes"))
    }
    func testNamedFillPreflightUsesOnlyTarget() throws {
        let clauses=try XCTUnwrap(GroundedSequence.clauses("Show Details then fill Message with Don't send this. Then delete Account!"))
        let plan=try GroundedSequence.preflightPlan(clauses)
        XCTAssertEqual(plan.texts,["Show Details","Focus Message"])
        XCTAssertEqual(plan.requiredOperations,[nil,"focus"])
        XCTAssertEqual(try GroundedSequence.textCommand(clauses[1])?.value,"Don't send this. Then delete Account!")
    }
    func testUnsupportedTextOperationRejectedBeforeExecution() {
        XCTAssertThrowsError(try GroundedSequence.preflightPlan(["Show Tools","search this site for cats"]))
        XCTAssertThrowsError(try GroundedSequence.preflightPlan(["Show Tools","type"]))
        XCTAssertThrowsError(try GroundedSequence.preflightPlan(["Show Tools","type "+String(repeating:"x",count:16001)]))
    }
    func testTypingPreflightRequiresFocusRatherThanActivation() throws {
        let activate=try JSONDecoder().decode(GroundedPreflight.self,from:Data(#"{"id":"r","operations":[{"operation":"activate","confidence":0.999}]}"#.utf8))
        XCTAssertFalse(activate.accepts(requestID:"r",count:1,requiredOperations:["focus"]))
        let focus=try JSONDecoder().decode(GroundedPreflight.self,from:Data(#"{"id":"r","operations":[{"operation":"focus","confidence":0.999}]}"#.utf8))
        XCTAssertTrue(focus.accepts(requestID:"r",count:1,requiredOperations:["focus"]))
        XCTAssertFalse(focus.accepts(requestID:"stale",count:1,requiredOperations:["focus"]))
    }
    private func observation(focus:String="field",document:String="doc",enabled:Bool=true) throws -> BrowserObservation {
        let json="""
        {"version":1,"documentId":"\(document)","observationId":"fresh","origin":"https://example.test","capturedAt":10000,"revision":1,"viewport":{"width":100,"height":100,"scale":1},"focusedId":"\(focus)","truncated":false,"candidates":[{"id":"field","role":"input","labels":["Message"],"bounds":{"x":1,"y":1,"width":80,"height":20},"enabled":\(enabled),"editable":true,"clickable":true}]}
        """
        return try JSONDecoder().decode(BrowserObservation.self,from:Data(json.utf8))
    }
    func testTypeRequiresSameVerifiedFocusedFieldAndFreshState() throws {
        let focus=BrowserCommand(op:"click",targetId:"field",documentId:"doc",observationId:"old")
        let command=try GroundedSequence.bindType("literal",after:focus,observation:observation(),nowMs:10100)
        XCTAssertEqual(command.op,"type");XCTAssertEqual(command.observationId,"fresh")
        XCTAssertThrowsError(try GroundedSequence.bindType("literal",after:focus,observation:observation(focus:"other"),nowMs:10100))
        XCTAssertThrowsError(try GroundedSequence.bindType("literal",after:focus,observation:observation(document:"other"),nowMs:10100))
        XCTAssertThrowsError(try GroundedSequence.bindType("literal",after:focus,observation:observation(enabled:false),nowMs:10100))
        XCTAssertThrowsError(try GroundedSequence.bindType("literal",after:focus,observation:observation(),nowMs:14000))
    }
}
