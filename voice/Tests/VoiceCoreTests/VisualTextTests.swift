import XCTest
import CoreGraphics
@testable import VoiceCore

final class VisualTextTests: XCTestCase {
    let frame = CGRect(x: -1000, y: 80, width: 1000, height: 600)
    let button = CGRect(x: -900, y: 140, width: 200, height: 70)
    func candidate(_ id: String = "save", labels: [String] = [], bounds: CGRect? = nil, enabled: Bool = true) -> VisualTargetPolicy.Candidate {
        .init(id: id, labels: labels, bounds: bounds ?? button, enabled: enabled)
    }
    func text(_ value: String = "Save", bounds: CGRect? = nil, confidence: Float = 1) -> VisualTextEvidence.Region {
        .init(text: value, normalizedBounds: bounds ?? CGRect(x: 0.12, y: 0.82, width: 0.10, height: 0.06), confidence: confidence)
    }
    func augmented(_ candidates: [VisualTargetPolicy.Candidate], _ regions: [VisualTextEvidence.Region]) -> [VisualTargetPolicy.Candidate] {
        VisualTextEvidence.augment(candidates, regions: regions, frame: frame)
    }
    func testVisibleTextAddsEvidenceToAnOtherwiseUnnamedControl() {
        let observed = [candidate()]
        XCTAssertNil(VisualTargetPolicy.select(point: [0.2, 0.16], candidates: observed, target: "Save", frame: frame))
        let result = augmented(observed, [text()])
        XCTAssertEqual(result.first?.id, "save")
        XCTAssertEqual(result.first?.bounds, button)
        XCTAssertEqual(VisualTargetPolicy.select(point: [0.2, 0.16], candidates: result, target: "Save", frame: frame)?.id, "save")
        XCTAssertEqual(observed.first?.labels, []) // Execution still rechecks the original AX snapshot.
    }
    func testOCRNeverOverridesConflictingAccessibleName() {
        let result = augmented([candidate(labels: ["Delete"])], [text()])
        XCTAssertEqual(result.first?.labels, ["Delete"])
        XCTAssertTrue(VisualTargetPolicy.eligible(result, target: "Save", frame: frame).isEmpty)
    }
    func testLowConfidenceInvalidAndUncontainedTextCannotNameAControl() {
        let cases = [text(confidence: 0.2), text(confidence: .nan), text(bounds: .zero),
                     text(bounds: CGRect(x: 0.05, y: 0.82, width: 0.1, height: 0.06)),
                     text(bounds: CGRect(x: 0.1, y: 0.99, width: 0.1, height: 0.06)), text(" ")]
        for region in cases {
            XCTAssertEqual(augmented([candidate()], [region]).first?.labels, [])
        }
    }
    func testOverlappingOwnersAndMultipleTextLinesRemainAmbiguous() {
        for enabled in [true, false] {
            let result = augmented([candidate(), candidate("other", enabled: enabled)], [text()])
            XCTAssertTrue(result.allSatisfy { $0.labels.isEmpty })
        }
        XCTAssertEqual(augmented([candidate()], [text(), text("Delete")]).first?.labels, [])
    }
    func testDisabledAndOffscreenControlsDoNotGainEvidence() {
        XCTAssertEqual(augmented([candidate(enabled: false)], [text()]).first?.labels, [])
        XCTAssertEqual(augmented([candidate(bounds: CGRect(x: -1100, y: 80, width: 400, height: 200))], [text()]).first?.labels, [])
    }
    func testDuplicateVisibleLabelsStillNeedAUserDisambiguator() {
        let second = CGRect(x: -300, y: 140, width: 200, height: 70)
        let result = augmented([candidate(), candidate("second", bounds: second)], [text(), text(bounds: CGRect(x: 0.72, y: 0.82, width: 0.1, height: 0.06))])
        XCTAssertNil(VisualTargetPolicy.select(point: [0.2, 0.16], candidates: result, target: "Save", frame: frame))
        XCTAssertEqual(VisualTargetPolicy.select(point: [0.2, 0.16], candidates: result, target: "left Save", frame: frame)?.id, "save")
    }
    func testOldPointCannotBypassFreshDuplicateOrRelabeledScene() {
        let second = CGRect(x: -300, y: 140, width: 200, height: 70)
        let controls = [candidate(), candidate("second", bounds: second)]
        let secondText = CGRect(x: 0.72, y: 0.82, width: 0.1, height: 0.06)
        let before = augmented(controls, [text(), text("Cancel", bounds: secondText)])
        XCTAssertEqual(VisualTargetPolicy.select(point: [0.2, 0.16], candidates: before, target: "Save", frame: frame)?.id, "save")
        let duplicate = augmented(controls, [text(), text("Save", bounds: secondText)])
        XCTAssertNil(VisualTargetPolicy.select(point: [0.2, 0.16], candidates: duplicate, target: "Save", frame: frame))
        let renamed = augmented(controls, [text("Delete"), text("Cancel", bounds: secondText)])
        XCTAssertNil(VisualTargetPolicy.select(point: [0.2, 0.16], candidates: renamed, target: "Save", frame: frame))
    }
}
