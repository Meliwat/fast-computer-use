import XCTest
@testable import VoiceCore
final class GroundedProposalTests: XCTestCase {
    private func observation() throws -> BrowserObservation {
        try JSONDecoder().decode(BrowserObservation.self,from:Data(#"{"version":1,"documentId":"doc","observationId":"obs","origin":"https://example.test","capturedAt":10000,"revision":0,"viewport":{"width":100,"height":100,"scale":1},"truncated":false,"candidates":[{"id":"field","role":"input","labels":["Search"],"bounds":{"x":1,"y":1,"width":40,"height":20},"enabled":true,"editable":true,"clickable":true},{"id":"link","role":"a","labels":["Home"],"bounds":{"x":1,"y":30,"width":40,"height":20},"enabled":true,"editable":false,"clickable":true}]}"#.utf8))
    }
    private func reply(op:String="click",target:String="field",document:String="doc",observation:String="obs",operation:String="focus",extra:String="") throws -> GroundedProposal {
        let json="""
        {"id":"request","command":{"op":"\(op)","targetId":"\(target)","documentId":"\(document)","observationId":"\(observation)"\(extra)},"reason":"bound","operation":{"operation":"\(operation)","confidence":0.999},"milliseconds":1.2}
        """
        return try JSONDecoder().decode(GroundedProposal.self,from:Data(json.utf8))
    }
    func testBoundFocusRoundTrip() throws {
        let obs=try observation()
        let roundtrip=try JSONDecoder().decode(BrowserObservation.self,from:JSONEncoder().encode(obs))
        XCTAssertEqual(try reply().validatedCommand(for:roundtrip,requestID:"request",nowMs:10100)?.targetId,"field")
    }
    func testRejectsStaleWrongDocumentUnknownTargetAndWrongReply() throws {
        let obs=try observation()
        XCTAssertThrowsError(try reply().validatedCommand(for:obs,requestID:"other",nowMs:10100))
        XCTAssertThrowsError(try reply().validatedCommand(for:obs,requestID:"request",nowMs:13000))
        XCTAssertThrowsError(try reply(document:"other").validatedCommand(for:obs,requestID:"request",nowMs:10100))
        XCTAssertThrowsError(try reply(target:"invented").validatedCommand(for:obs,requestID:"request",nowMs:10100))
        XCTAssertThrowsError(try reply(observation:"old").validatedCommand(for:obs,requestID:"request",nowMs:10100))
    }
    func testCannotEscalateOperationOrSupplyUnrequestedText() throws {
        let obs=try observation()
        XCTAssertThrowsError(try reply(op:"fill",extra:",\"value\":\"hello\"").validatedCommand(for:obs,requestID:"request",nowMs:10100))
        XCTAssertThrowsError(try reply(extra:",\"target\":\"Home\"").validatedCommand(for:obs,requestID:"request",nowMs:10100))
        XCTAssertThrowsError(try reply(operation:"activate").validatedCommand(for:obs,requestID:"request",nowMs:10100))
        XCTAssertThrowsError(try reply(operation:"delete").validatedCommand(for:obs,requestID:"request",nowMs:10100))
    }
    func testAbstentionDoesNotGenerateAnAction() throws {
        let reply=try JSONDecoder().decode(GroundedProposal.self,from:Data(#"{"id":"request","command":null,"reason":"uncertain"}"#.utf8))
        XCTAssertNil(try reply.validatedCommand(for:observation(),requestID:"request",nowMs:10100))
    }
}
