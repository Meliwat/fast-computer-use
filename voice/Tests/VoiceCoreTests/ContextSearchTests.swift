import XCTest
@testable import VoiceCore
final class ContextSearchTests: XCTestCase {
    func testBrowserSearchKeepsQueryLiteral() {
        XCTAssertEqual(Parser.parse("search for cats and open Notes", browserContext:true), [BrowserCommand(op:"search",value:"cats and open Notes").command])
        XCTAssertTrue(Parser.hasDictation("search for local agents"))
    }
    func testExplicitWebSearchAndOtherApps() {
        XCTAssertEqual(Parser.parse("Google local agents", browserContext:true), [Command(.searchWeb,"local agents")])
        XCTAssertEqual(Parser.parse("search the web for local agents", browserContext:true), [Command(.searchWeb,"local agents")])
        XCTAssertEqual(Parser.parse("search for local agents"), [Command(.searchWeb,"local agents")])
    }
    func testBrowserClickRetainsRoleWording() {
        XCTAssertEqual(Parser.parse("click the Search button", browserContext:true),[Command(.clickControl,"Search button")])
        XCTAssertEqual(Parser.parse("click the Search field", browserContext:true),[Command(.clickControl,"Search field")])
    }
    func testSearchWaitsForFinalTranscript() {
        var scheduler=Scheduler()
        XCTAssertEqual(scheduler.update("search for local agents",final:false,now:1,browserContext:true),[])
        XCTAssertEqual(scheduler.update("search for local agents",final:true,now:2,browserContext:true),[BrowserCommand(op:"search",value:"local agents").command])
    }
}
