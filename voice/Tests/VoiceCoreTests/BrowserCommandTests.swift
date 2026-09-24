import XCTest
@testable import VoiceCore
final class BrowserCommandTests: XCTestCase {
    func testGenericCommands() throws {
        let cases: [(String, BrowserCommand)] = [
            ("fill Destination with Oslo", BrowserCommand(op:"fill",target:"Destination",value:"Oslo")),
            ("choose Canada from the Region dropdown", BrowserCommand(op:"select",target:"Region",value:"Canada")),
            ("check Email updates", BrowserCommand(op:"check",target:"Email updates",checked:true)),
            ("uncheck Email updates", BrowserCommand(op:"check",target:"Email updates",checked:false)),
            ("search this site for wooden toys", BrowserCommand(op:"search",value:"wooden toys")),
            ("scroll down", BrowserCommand(op:"scroll",value:"down")),
            ("next tab", BrowserCommand(op:"nextTab"))
        ]
        for (text, expected) in cases {
            let commands=Parser.parse(text)
            XCTAssertEqual(commands.count,1,text)
            XCTAssertEqual(try BrowserCommand.decode(XCTUnwrap(commands.first).value),expected,text)
        }
    }
    func testLiteralPayloadAndExistingTitle() {
        XCTAssertEqual(Parser.parse("set the title to hello"),[Command(.titleNote,"hello")])
        XCTAssertEqual(Parser.parse("fill Message with don't open Notes and click Send"),[BrowserCommand(op:"fill",target:"Message",value:"don't open Notes and click Send").command])
        XCTAssertTrue(Parser.hasDictation("fill Message with hello"))
        XCTAssertTrue(Parser.hasDictation("search this site for toys"))
        XCTAssertEqual(Parser.parse("don't check Email updates"),[])
    }
    func testNamedSectionQualifiersReachBrowserWithoutChangingLiteralValues() {
        let cases: [(String, Command)] = [
            ("click Save button in the Profile section",Command(.clickControl,"Save button in the Profile section")),
            ("fill Email in the Billing form with local@example.test",BrowserCommand(op:"fill",target:"Email in the Billing form",value:"local@example.test").command),
            ("choose Canada from Country in Shipping section",BrowserCommand(op:"select",target:"Country in Shipping section",value:"Canada").command),
            ("check Updates in Billing group",BrowserCommand(op:"check",target:"Updates in Billing group",checked:true).command),
            ("copy Email in Profile section into Email in Billing section",BrowserCommand(op:"copyText",target:"Email in Billing section",source:"Email in Profile section").command),
            ("make Email in Billing section uppercase",BrowserCommand(op:"changeCase",target:"Email in Billing section",value:"uppercase").command),
            ("fill Message in Profile section with click Save in Billing section",BrowserCommand(op:"fill",target:"Message in Profile section",value:"click Save in Billing section").command)
        ]
        for (text,expected) in cases { XCTAssertEqual(Parser.parse(text,browserContext:true),[expected],text) }
    }
}
