import XCTest
@testable import VoiceCore

final class NativeTextTests: XCTestCase {
    private func field(_ labels:[String], visible:Bool=true, enabled:Bool=true, secure:Bool=false, writable:Bool=true) -> NativeTextTarget.Candidate {
        .init(labels:labels,visible:visible,enabled:enabled,secure:secure,writable:writable)
    }
    func testUniqueNativeFieldAndRoleSuffix() {
        let fields=[field(["Destination"]),field(["Message"])]
        XCTAssertEqual(NativeTextTarget.uniqueIndex(target:" destination field ",candidates:fields),0)
        XCTAssertEqual(NativeTextTarget.uniqueIndex(target:"Message",candidates:fields),1)
        XCTAssertEqual(NativeTextTarget.uniqueIndex(target:"First name",candidates:[field(["First name:"])]),0)
        XCTAssertNil(NativeTextTarget.uniqueIndex(target:"Password",candidates:fields))
        XCTAssertEqual(NativeTextTarget.uniqueIndex(target:"Name field",candidates:[field(["Name"]),field(["Name field"])]),1)
    }
    func testAmbiguousProtectedAndReadOnlyTargetsStop() {
        XCTAssertNil(NativeTextTarget.uniqueIndex(target:"Name",candidates:[field(["Name"]),field(["Name"])]))
        XCTAssertNil(NativeTextTarget.uniqueIndex(target:"Name",candidates:[field(["Name"],enabled:false)]))
        XCTAssertNil(NativeTextTarget.uniqueIndex(target:"Name",candidates:[field(["Name"],secure:true)]))
        XCTAssertNil(NativeTextTarget.uniqueIndex(target:"Name",candidates:[field(["Name"],writable:false)]))
        XCTAssertEqual(NativeTextTarget.uniqueIndex(target:"Name",candidates:[field(["Name"],visible:false),field(["Name"])]),1)
    }
    func testFirstMatchMustPersistAndReversionCannotRecover() {
        var check=NativeTextVerification(before:"old",expected:"new",startedAt:0)
        XCTAssertEqual(check.observe(value:"new",sameContext:true,at:0),.waiting)
        XCTAssertEqual(check.observe(value:"new",sameContext:true,at:0.1),.waiting)
        XCTAssertEqual(check.observe(value:"old",sameContext:true,at:0.12),.failed)
        XCTAssertEqual(check.observe(value:"new",sameContext:true,at:0.3),.failed)
    }
    func testAsynchronousWriteCanSettleWithoutAnotherMutation() {
        var check=NativeTextVerification(before:"old",expected:"new",startedAt:5)
        XCTAssertEqual(check.observe(value:"old",sameContext:true,at:5.05),.waiting)
        XCTAssertEqual(check.observe(value:"new",sameContext:true,at:5.1),.waiting)
        XCTAssertEqual(check.observe(value:"new",sameContext:true,at:5.29),.verified)
    }
    func testFocusChangeUnknownValueTimeoutAndWrongTextNeverVerify() {
        for kind in 0..<5 {
            var check=NativeTextVerification(before:"old",expected:"new",startedAt:1)
            _=check.observe(value:"old",sameContext:true,at:1)
            let result=check.observe(value:kind==1 ? nil : kind==3 ? "unexpected" : "new",sameContext:kind != 0,at:kind==2 ? 1.6 : kind==4 ? 0.9 : 1.1)
            XCTAssertEqual(result,.failed)
        }
    }
    func testFillKeepsTheSpokenValueLiteral() throws {
        let command=try XCTUnwrap(Parser.parse("fill Destination with Oslo and open Notes").first)
        XCTAssertEqual(try BrowserCommand.decode(command.value),BrowserCommand(op:"fill",target:"Destination",value:"Oslo and open Notes"))
    }
    func testExactFocusUsesNativeRouteAndKeepsBrowserGrounding() {
        XCTAssertEqual(Parser.parse("Focus City"),[Command(.focusControl,"City")])
        XCTAssertEqual(Parser.parse("focus on the Email address field"),[Command(.focusControl,"Email address field")])
        XCTAssertTrue(Parser.parse("Do not focus City").isEmpty)
        XCTAssertTrue(Parser.parse("Focus City",browserContext:true).isEmpty)
        XCTAssertEqual(Parser.parse("open Notes then focus Search"),[Command(.openApp,"com.apple.Notes"),Command(.focusControl,"Search")])
        XCTAssertEqual(Parser.parse("focus Subject then type hello and open Notes"),[Command(.focusControl,"Subject"),Command(.typeText,"hello and open Notes")])
    }
}
