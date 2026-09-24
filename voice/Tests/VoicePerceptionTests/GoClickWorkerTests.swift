import XCTest
import ImageIO
@testable import VoicePerception
final class GoClickWorkerTests: XCTestCase {
    private func stub(_ body: String) throws -> (GoClickWorker,URL) {
        let python="/usr/bin/python3"
        guard FileManager.default.isExecutableFile(atPath:python) else { throw XCTSkip("Python is unavailable for protocol fixture") }
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let script=root.appendingPathComponent("fixture.py")
        try ("import sys,json\nfor line in sys.stdin:\n r=json.loads(line)\n"+body+"\n").write(to:script,atomically:true,encoding:.utf8)
        return (GoClickWorker(configuration:["python":python,"worker":script.path,"model":root.path]),root)
    }
    func testRepliesMustMatchBothRequestAndFrame() async throws {
        for body in [
            " print(json.dumps(dict(id='wrong',ok=True)),flush=True)",
            " print(json.dumps(dict(id=r['id'],ok=True,frameId='old',point=[.5,.5])),flush=True)"
        ] {
            let (worker,root)=try stub(body)
            defer { worker.shutdown();try? FileManager.default.removeItem(at:root) }
            do { _ = try await worker.predict(frameID:"current",target:"Settings");XCTFail("A stale reply was accepted") }
            catch { XCTAssertTrue(error.localizedDescription.contains("identity mismatch")) }
        }
    }
    func testWorkerRejectionPropagatesAndClearDoesNotSpawn() async throws {
        let (worker,root)=try stub(" print(json.dumps(dict(id=r['id'],ok=False,error='Visual frame expired; capture again')),flush=True)")
        defer { worker.shutdown();try? FileManager.default.removeItem(at:root) }
        do { _ = try await worker.predict(frameID:"expired",target:"Settings");XCTFail("Rejection was ignored") }
        catch { XCTAssertTrue(error.localizedDescription.contains("expired")) }
        let missing=GoClickWorker(configuration:["python":"/not/installed"])
        await missing.clear() // Clearing an idle client needs no runtime installation.
    }
    func testSameSizedTinyPixelChangeInvalidatesDigestAndEncodingBoundsImage() throws {
        let width=2048,height=1024
        let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray:1,alpha:1);context.fill(CGRect(x:0,y:0,width:width,height:height))
        let before=context.makeImage()!
        XCTAssertEqual(ScreenObserver.digest(before),ScreenObserver.digest(before))
        context.setFillColor(gray:0,alpha:1);context.fill(CGRect(x:15,y:20,width:1,height:1))
        XCTAssertNotEqual(ScreenObserver.digest(before),ScreenObserver.digest(context.makeImage()!))
        let data=try GoClickWorker.encode(before)
        let source=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
        let decoded=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertEqual(decoded.width,1024);XCTAssertEqual(decoded.height,512)
    }
}
