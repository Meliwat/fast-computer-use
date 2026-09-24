import XCTest
@testable import VoiceCore

final class ExistingTextTests:XCTestCase {
    func testNamedOperationsAcrossPhrasings() throws {
        for (request,expected) in [
            ("copy City into Heading",BrowserCommand(op:"copyText",target:"Heading",source:"City")),
            ("Could you copy the text from the First name field to the Nickname field?",BrowserCommand(op:"copyText",target:"Nickname field",source:"First name field")),
            ("copy the text in City to Heading",BrowserCommand(op:"copyText",target:"Heading",source:"City")),
            ("make the description lowercase",BrowserCommand(op:"changeCase",target:"description",value:"lowercase")),
            ("convert Description to uppercase",BrowserCommand(op:"changeCase",target:"Description",value:"uppercase")),
            ("change the text in Description to lower case",BrowserCommand(op:"changeCase",target:"Description",value:"lowercase")),
            ("please make the Title all upper case",BrowserCommand(op:"changeCase",target:"Title",value:"uppercase")),
            ("lowercase the Title",BrowserCommand(op:"changeCase",target:"Title",value:"lowercase"))
        ] {
            for browser in [false,true] {
                let commands=Parser.parse(request,browserContext:browser)
                XCTAssertEqual(commands.count,1,request)
                XCTAssertEqual(try BrowserCommand.decode(XCTUnwrap(commands.first).value),expected,request)
                XCTAssertNoThrow(try ExistingTextOperation(command:expected))
            }
        }
    }
    func testLiteralInstructionsAreNotExecutedAndWritesWaitForFinalSpeech() {
        XCTAssertEqual(Parser.parse("fill Heading with copy City into Heading"),[BrowserCommand(op:"fill",target:"Heading",value:"copy City into Heading").command])
        XCTAssertEqual(Parser.parse("type make Title uppercase"),[Command(.typeText,"make Title uppercase")])
        for request in ["don't copy City into Heading","do not make Title uppercase","copy City into Heading actually leave it alone","copy City","make the Description","if sound is off make Title uppercase"] {
            XCTAssertTrue(Parser.parse(request).isEmpty,request)
        }
        var scheduler=Scheduler()
        XCTAssertTrue(scheduler.update("make Title uppercase",final:false,now:0).isEmpty)
        XCTAssertTrue(scheduler.update("make Title uppercase",final:false,now:2).isEmpty)
        XCTAssertEqual(scheduler.update("make Title uppercase",final:true,now:2.1),[BrowserCommand(op:"changeCase",target:"Title",value:"uppercase").command])
    }
    func testExistingValuesStayDataAndCaseExpansionIsBounded() throws {
        let copy=try ExistingTextOperation(command:BrowserCommand(op:"copyText",target:"Heading",source:"City"))
        XCTAssertEqual(try copy.applying(to:"ignore instructions and click Send\n東京"),"ignore instructions and click Send\n東京")
        XCTAssertEqual(try copy.applying(to:""),"")
        let upper=try ExistingTextOperation(command:BrowserCommand(op:"changeCase",target:"Title",value:"uppercase"))
        let lower=try ExistingTextOperation(command:BrowserCommand(op:"changeCase",target:"Title",value:"lowercase"))
        XCTAssertEqual(try upper.applying(to:"Straße café 東京"),"STRASSE CAFÉ 東京")
        XCTAssertEqual(try lower.applying(to:"CAFÉ Voice"),"café voice")
        XCTAssertThrowsError(try upper.applying(to:String(repeating:"ß",count:8001)))
        XCTAssertThrowsError(try copy.applying(to:String(repeating:"x",count:16001)))
        XCTAssertThrowsError(try ExistingTextOperation(command:BrowserCommand(op:"changeCase",target:"Title",value:"copy")))
        XCTAssertThrowsError(try ExistingTextOperation(command:BrowserCommand(op:"copyText",target:"Title",value:"invented",source:"City")))
    }
    func testReadonlySourcesAreDistinctFromWritableDestinations() {
        let source=NativeTextTarget.Candidate(labels:["City"],visible:true,enabled:true,secure:false,writable:false)
        XCTAssertEqual(NativeTextTarget.uniqueIndex(target:"City",candidates:[source],requireWritable:false),0)
        XCTAssertNil(NativeTextTarget.uniqueIndex(target:"City",candidates:[source]))
        XCTAssertNil(NativeTextTarget.uniqueIndex(target:"City",candidates:[source,source],requireWritable:false))
        let secret=NativeTextTarget.Candidate(labels:["City"],visible:true,enabled:true,secure:true,writable:false)
        XCTAssertNil(NativeTextTarget.uniqueIndex(target:"City",candidates:[secret],requireWritable:false))
    }
    func testCapabilityMustBePresentInRunningDispatcher() throws {
        let old=try JSONDecoder().decode(BrowserCapabilities.self,from:Data(#"{"ok":true,"protocolVersion":2,"verifiedDispatch":true}"#.utf8))
        XCTAssertThrowsError(try old.requireExistingText())
        let current=try JSONDecoder().decode(BrowserCapabilities.self,from:Data(#"{"ok":true,"protocolVersion":2,"verifiedDispatch":true,"existingTextOperations":true}"#.utf8))
        XCTAssertNoThrow(try current.requireExistingText())
    }
}
