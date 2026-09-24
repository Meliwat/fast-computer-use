import XCTest
@testable import VoiceCore
final class RuntimeConfigurationTests:XCTestCase {
    func testMovedBundleResolvesWorkersAndModelsWithoutSourceCheckout() throws {
        let root=URL(fileURLWithPath:"/tmp/Moved App.app/Contents/Resources")
        let result=try RuntimeConfiguration.resolve(["worker":"Runtime/grounded/worker.py","models":"Runtime/models","python":"/opt/runtime/bin/python"],resources:root)
        XCTAssertEqual(result["worker"],root.appendingPathComponent("Runtime/grounded/worker.py").path)
        XCTAssertEqual(result["models"],root.appendingPathComponent("Runtime/models").path)
        XCTAssertEqual(result["python"],"/opt/runtime/bin/python")
    }
    func testRejectsEmptyOrEscapingRelativePaths() {
        let root=URL(fileURLWithPath:"/tmp/App/Resources")
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(["worker":"../outside.py"],resources:root))
        XCTAssertThrowsError(try RuntimeConfiguration.resolve(["worker":""],resources:root))
    }
}
