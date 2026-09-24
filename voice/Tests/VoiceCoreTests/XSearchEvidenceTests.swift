import XCTest
@testable import VoiceCore
final class XSearchEvidenceTests:XCTestCase {
    private func evidence(query:Bool=true,loaded:Bool=true,signature:String="new",document:String="doc") throws -> XSearchEvidence {
        let json="""
        {"supported":true,"queryMatches":\(query),"loaded":\(loaded),"signature":"\(signature)","documentId":"\(document)","visibleResults":2}
        """
        return try JSONDecoder().decode(XSearchEvidence.self,from:Data(json.utf8))
    }
    func testMatchingLoadedResultsRequireNewEvidenceAfterSubmission() throws {
        let before=try evidence(query:false,signature:"old")
        XCTAssertTrue(try evidence().verifies(after:before))
        XCTAssertFalse(try evidence(query:false).verifies(after:before))
        XCTAssertFalse(try evidence(loaded:false).verifies(after:before))
        XCTAssertFalse(try evidence(signature:"old").verifies(after:before))
        XCTAssertFalse(try evidence(signature:"").verifies(after:before))
    }
    func testNewDocumentMayShowSameResultsButMustMatchQuery() throws {
        XCTAssertTrue(try evidence(signature:"old",document:"newdoc").verifies(after:evidence(query:false,signature:"old")))
        XCTAssertFalse(try evidence(query:false,signature:"old",document:"newdoc").verifies(after:evidence(query:false,signature:"old")))
    }
}
