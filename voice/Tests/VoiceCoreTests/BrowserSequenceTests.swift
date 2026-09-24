import XCTest
@testable import VoiceCore

final class BrowserSequenceTests: XCTestCase {
    func testExactSequencesSkipLanguageModelAndPreserveLiteralTail() throws {
        let plan=try XCTUnwrap(BrowserSequence.plan("click Details then focus Message then type Hello, then click Send!"))
        XCTAssertTrue(plan.preflightTexts.isEmpty)
        XCTAssertEqual(plan.steps.count,3)
        XCTAssertEqual(plan.steps.last?.command?.value,"Hello, then click Send!")
        XCTAssertTrue(plan.steps[1].requiresFocus)
        XCTAssertNil(try BrowserSequence.plan("type Hello then click Send"))
        XCTAssertNil(try BrowserSequence.plan("open Codex then new chat"))
    }
    func testMixedSequenceChecksOnlyUnknownPhrasing() throws {
        let plan=try XCTUnwrap(BrowserSequence.plan("Show the tools menu then fill Message with Hello"))
        XCTAssertEqual(plan.preflightTexts,["Show the tools menu"])
        XCTAssertEqual(plan.requiredOperations.count,1)
        XCTAssertNil(plan.requiredOperations[0])
        XCTAssertEqual(plan.steps[1].command?.op,"fill")
    }
    func testAndSequencesAndWholePlanValidation() throws {
        XCTAssertEqual(try BrowserSequence.plan("check Filters and click Details")?.steps.count,2)
        XCTAssertThrowsError(try BrowserSequence.plan("click Details then send it"))
        XCTAssertThrowsError(try BrowserSequence.plan("click Details then search this site for cats"))
        XCTAssertThrowsError(try BrowserSequence.plan("click A then click B then click C then click D"))
        XCTAssertThrowsError(try BrowserSequence.plan("check Filters then type text"))
        XCTAssertEqual(try BrowserSequence.plan("click Message then type Hello")?.steps.first?.requiresFocus,true)
    }
    func testBrowserMutationsWaitForFinalTranscript() {
        var scheduler=Scheduler()
        for now in [0.0,0.6,2.0] {
            XCTAssertEqual(scheduler.update("click Details then click Save",final:false,now:now,browserContext:true),[])
        }
        XCTAssertEqual(scheduler.update("click Details then click Save",final:true,now:3,browserContext:true).count,2)
    }
    private func observation(document:String="doc",focus:String?=nil) throws -> BrowserObservation {
        let data=Data("""
        {"version":1,"documentId":"\(document)","observationId":"fresh","origin":"https://example.test","url":"https://example.test/","capturedAt":10000,"revision":0,"viewport":{"width":100,"height":100,"scale":1},"targetQuery":"Details","focusedId":\(focus.map { "\"\($0)\"" } ?? "null"),"truncated":false,"candidates":[{"id":"details","role":"button","labels":["details"],"bounds":{"x":1,"y":1,"width":80,"height":20},"enabled":true,"editable":false,"clickable":true}]}
        """.utf8)
        return try JSONDecoder().decode(BrowserObservation.self,from:data)
    }
    @MainActor func testUnverifiedExactActionStopsWithoutResolvingOrSendingLaterStep() async throws {
        let plan=try XCTUnwrap(BrowserSequence.plan("click Details then fill Message with Hello"))
        var observed=0,sent=0,modelCalls=0
        do {
            _=try await BrowserSequence.run(plan,preflight:{_,_ in modelCalls+=1;return true},stillValid:{true},observe:{_ in observed+=1;return try self.observation()},propose:{_,_ in modelCalls+=1;return nil},dispatch:{_,_ in sent+=1;return false},nowMs:{10100})
            XCTFail("must stop")
        } catch { XCTAssertTrue(error.localizedDescription.contains("step 1")) }
        XCTAssertEqual(observed,1);XCTAssertEqual(sent,1);XCTAssertEqual(modelCalls,0)
    }
    @MainActor func testDocumentChangeAfterVerifiedClickStopsSequence() async throws {
        let plan=try XCTUnwrap(BrowserSequence.plan("click Details then click Save"))
        var observed=0,sent=0
        do {
            _=try await BrowserSequence.run(plan,preflight:{_,_ in true},stillValid:{true},observe:{_ in observed+=1;return try self.observation(document:observed==1 ? "doc":"other")},propose:{_,_ in nil},dispatch:{_,_ in sent+=1;return true},nowMs:{10100})
            XCTFail("must stop")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Page changed")) }
        XCTAssertEqual(sent,1)
    }
    @MainActor func testCancellationAfterObservationSendsNothing() async throws {
        let plan=try XCTUnwrap(BrowserSequence.plan("click Details then click Save"))
        var valid=true,sent=0
        do {
            _=try await BrowserSequence.run(plan,preflight:{_,_ in true},stillValid:{valid},observe:{_ in valid=false;return try self.observation()},propose:{_,_ in nil},dispatch:{_,_ in sent+=1;return true},nowMs:{10100})
            XCTFail("must stop")
        } catch { XCTAssertEqual(sent,0) }
    }

    @MainActor func testVerifiedNavigationCarriesOnlyObservedDestination() async throws {
        let plan=try XCTUnwrap(BrowserSequence.plan("click Details then click Details"))
        for correct in [true,false] {
            var observations=0,sent:[String]=[]
            do {
                let count=try await BrowserSequence.run(plan,preflight:{_,_ in true},stillValid:{true},observe:{_ in
                    observations+=1
                    var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(self.observation(document:observations==1 ? "doc":"next"))) as! [String:Any]
                    object["url"]=observations==1 ? "https://example.test/" : (correct ? "https://example.test/details":"https://example.test/wrong")
                    if observations==1 {
                        var candidates=object["candidates"] as! [[String:Any]]
                        candidates[0]["navigationURL"]="https://example.test/details";object["candidates"]=candidates
                    }
                    return try JSONDecoder().decode(BrowserObservation.self,from:JSONSerialization.data(withJSONObject:object))
                },propose:{_,_ in nil},dispatch:{command,_ in sent.append(command.documentId!);return true},nowMs:{10100})
                XCTAssertTrue(correct);XCTAssertEqual(count,2)
            } catch {XCTAssertFalse(correct);XCTAssertTrue(error.localizedDescription.contains("Destination changed"))}
            XCTAssertEqual(sent,correct ? ["doc","next"]:["doc"])
        }
    }
    @MainActor func testSlowProposalExpiresBeforeDispatch() async throws {
        let plan=try XCTUnwrap(BrowserSequence.plan("Show Details then fill Message with Hello"))
        var now=10100.0,sent=0
        do {
            _=try await BrowserSequence.run(plan,preflight:{_,_ in true},stillValid:{true},observe:{_ in try self.observation()},propose:{_,observation in
                now=14000
                return BrowserCommand(op:"click",targetId:"details",documentId:observation.documentId,observationId:observation.observationId)
            },dispatch:{_,_ in sent+=1;return true},nowMs:{now})
            XCTFail("must stop")
        } catch {XCTAssertTrue(error.localizedDescription.contains("expired"))}
        XCTAssertEqual(sent,0)
    }
}
