import XCTest
@testable import VoiceCore
final class AppCommandsTests: XCTestCase {
    func testWebsiteNamesAndSpokenDomains() {
        XCTAssertEqual(Parser.parse("go to GitHub"), [Command(.openURL,"https://github.com")])
        XCTAssertEqual(Parser.parse("visit YouTube"), [Command(.openURL,"https://www.youtube.com")])
        XCTAssertEqual(Parser.parse("open the website example dot com slash MyPage"), [Command(.openURL,"https://example.com/MyPage")])
        XCTAssertEqual(Parser.parse("navigate to https://EXAMPLE.com/MyPage?q=Hello"), [Command(.openURL,"https://example.com/MyPage?q=Hello")])
        XCTAssertEqual(Parser.parse("go to news dot ycombinator dot com"), [Command(.openURL,"https://news.ycombinator.com")])
    }
    func testWebsiteValidation() {
        for value in ["file:///etc/passwd", "javascript:alert(1)", "https://person:password@example.com", "some random website", "example..com"] {
            XCTAssertNil(WebDestination.resolve(value), value)
        }
    }
    func testCodexAndCompoundCommands() {
        XCTAssertEqual(Parser.parse("open Codex then start a new chat"), [Command(.openApp,"com.openai.codex"), Command(.newChat,"com.openai.codex")])
        XCTAssertEqual(Parser.parse("open a new chat in Codex"), [Command(.newChat,"com.openai.codex")])
        XCTAssertEqual(Parser.parse("Open Codex. Create a new conversation."), [Command(.openApp,"com.openai.codex"), Command(.newChat,"com.openai.codex")])
        XCTAssertEqual(AppActionRoute.chatURL(for:"com.openai.codex")?.absoluteString, "codex://threads/new")
        XCTAssertNil(AppActionRoute.chatURL(for:"com.apple.Safari"))
    }
    func testMoreAppActions() {
        XCTAssertEqual(Parser.parse("new tab in Safari"), [Command(.newTab,"com.apple.Safari")])
        XCTAssertEqual(Parser.parse("open Chrome and open a new tab"), [Command(.openApp,"com.google.Chrome"),Command(.newTab,"com.google.Chrome")])
        XCTAssertEqual(Parser.parse("create a new document in TextEdit"), [Command(.newDocument,"com.apple.TextEdit")])
        XCTAssertEqual(Parser.parse("open Calendar", apps:["calendar":"com.apple.iCal"]), [Command(.openApp,"com.apple.iCal")])
        XCTAssertEqual(Parser.parse("open Codex and create a new invoice"), [])
    }
    func testStreamingDoesNotRepeatCodexLaunch() {
        var scheduler = Scheduler()
        XCTAssertEqual(scheduler.update("open Codex",final:false,now:0), [])
        XCTAssertEqual(scheduler.update("open Codex",final:false,now:0.6), [Command(.openApp,"com.openai.codex")])
        XCTAssertEqual(scheduler.update("open Codex and start a new chat",final:true,now:1), [Command(.newChat,"com.openai.codex")])
    }
}
