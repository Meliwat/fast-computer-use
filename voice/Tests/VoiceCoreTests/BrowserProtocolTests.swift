import XCTest
@testable import VoiceCore
final class BrowserProtocolTests: XCTestCase {
    func testOperationalErrorDoesNotMasqueradeAsAnOutdatedExtension() throws {
        let reply=try JSONDecoder().decode(BrowserCapabilities.self,from:Data(#"{"ok":false,"error":"Chrome is not the foreground app"}"#.utf8))
        XCTAssertThrowsError(try reply.requireVerifiedDispatch()) { error in
            XCTAssertEqual(error.localizedDescription,"Chrome is not the foreground app")
        }
    }
    func testVerifiedDispatcherRequired() throws {
        for json in [#"{"ok":true,"protocolVersion":2,"verifiedDispatch":false}"#,
                     #"{"ok":true,"message":"old acknowledgement"}"#,
                     #"{"ok":false,"error":"Unsupported browser action"}"#] {
            let reply=try JSONDecoder().decode(BrowserCapabilities.self,from:Data(json.utf8))
            XCTAssertThrowsError(try reply.requireVerifiedDispatch()) { error in
                XCTAssertTrue(error.localizedDescription.contains("Reload Local Voice Browser"))
            }
        }
        let reply=try JSONDecoder().decode(BrowserCapabilities.self,from:Data(#"{"ok":true,"protocolVersion":2,"verifiedDispatch":true}"#.utf8))
        XCTAssertNoThrow(try reply.requireVerifiedDispatch())
    }

    func testSequenceDispatcherRequiresAdvertisedDocumentBinding() throws {
        for json in [#"{"ok":true,"protocolVersion":2,"verifiedDispatch":true}"#,
                     #"{"ok":true,"protocolVersion":2,"verifiedDispatch":true,"sequenceDispatch":false}"#,
                     #"{"ok":true,"protocolVersion":2,"verifiedDispatch":false,"sequenceDispatch":true}"#] {
            let reply=try JSONDecoder().decode(BrowserCapabilities.self,from:Data(json.utf8))
            XCTAssertThrowsError(try reply.requireSequenceDispatch())
        }
        let reply=try JSONDecoder().decode(BrowserCapabilities.self,from:Data(#"{"ok":true,"protocolVersion":2,"verifiedDispatch":true,"sequenceDispatch":true}"#.utf8))
        XCTAssertNoThrow(try reply.requireSequenceDispatch())
    }
}
