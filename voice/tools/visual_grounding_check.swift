// Offline synthetic UI evaluation. Never captures the desktop, reads an app,
// sends input, or requests permission. The only pixels are drawn below.
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import VoiceCore
import VoicePerception

struct Control {
    var id: String
    var visible: String
    var rect: CGRect
    var labels: [String] = []
    var enabled = true
}
struct Scene {
    let id: String
    let target: String
    let expected: String?
    let title: String
    var dark = false
    var controls: [Control]
}
func control(_ id: String, _ label: String, _ x: Double, _ y: Double, width: Double = 220, height: Double = 64, labels: [String] = [], enabled: Bool = true) -> Control {
    Control(id: id, visible: label, rect: CGRect(x: x, y: y, width: width, height: height), labels: labels, enabled: enabled)
}
let scenes: [Scene] = [
    Scene(id: "document", target: "Save", expected: "save", title: "Document editor", controls: [control("save", "Save", 900, 100), control("cancel", "Cancel", 640, 100)]),
    Scene(id: "sidebar", target: "Settings", expected: "settings", title: "Workspace", dark: true, controls: [control("home", "Home", 50, 120), control("files", "Files", 50, 230), control("settings", "Settings", 50, 580)]),
    Scene(id: "export", target: "Export", expected: "export", title: "Project files", controls: [control("import", "Import", 80, 150), control("export", "Export", 470, 440), control("archive", "Archive", 860, 150)]),
    Scene(id: "dialog", target: "Apply", expected: "apply", title: "Display preferences", dark: true, controls: [control("cancel", "Cancel", 280, 520), control("apply", "Apply", 760, 520)]),
    Scene(id: "search", target: "Search", expected: "search", title: "Knowledge library", controls: [control("browse", "Browse", 90, 190), control("search", "Search", 910, 190)]),
    Scene(id: "form", target: "Continue", expected: "continue", title: "New workspace", controls: [control("back", "Back", 100, 640), control("continue", "Continue", 900, 640)]),
    Scene(id: "position", target: "bottom Settings", expected: "bottom", title: "Two panels", controls: [control("top", "Settings", 500, 160), control("bottom", "Settings", 500, 590)]),
    Scene(id: "duplicate", target: "Settings", expected: nil, title: "Two panels", controls: [control("one", "Settings", 110, 350), control("two", "Settings", 820, 350)]),
    Scene(id: "absent", target: "Delete", expected: nil, title: "Document editor", controls: [control("save", "Save", 900, 100), control("cancel", "Cancel", 640, 100)]),
    Scene(id: "conflict", target: "Save", expected: nil, title: "Conflicting accessibility metadata", controls: [control("conflict", "Save", 500, 400, labels: ["Delete"])]),
    Scene(id: "disabled", target: "Submit", expected: nil, title: "Form incomplete", controls: [control("submit", "Submit", 900, 600, enabled: false)]),
    Scene(id: "overlap", target: "Save", expected: nil, title: "Overlapping controls", controls: [control("one", "Save", 500, 400), control("two", "Save", 500, 400)]),
    Scene(id: "wrapped-create", target: "Create new chat", expected: "create", title: "Conversations", controls: [control("create", "Create\nnew chat", 890, 140, width: 280, height: 110), control("cancel", "Cancel", 560, 140)]),
    Scene(id: "wrapped-sidebar", target: "Account preferences", expected: "account", title: "Workspace", dark: true, controls: [control("home", "Home", 50, 120), control("account", "Account\npreferences", 50, 380, width: 270, height: 110)]),
    Scene(id: "wrapped-three", target: "Create a new workspace", expected: "create", title: "Projects", controls: [control("create", "Create\na new\nworkspace", 690, 430, width: 270, height: 145)]),
    Scene(id: "wrapped-duplicate", target: "Open settings", expected: nil, title: "Two panels", controls: [control("one", "Open\nsettings", 140, 350, height: 110), control("two", "Open\nsettings", 840, 350, height: 110)]),
    Scene(id: "wrapped-conflict", target: "Create new chat", expected: nil, title: "Conflicting accessibility metadata", controls: [control("conflict", "Create\nnew chat", 500, 400, height: 110, labels: ["Delete"])]),
    Scene(id: "separated-lines", target: "Save Delete", expected: nil, title: "Separated text", controls: [control("separate", "Save\n\nDelete", 500, 400, height: 170)]),
    Scene(id: "wrapped-disabled", target: "Submit request", expected: nil, title: "Form incomplete", controls: [control("submit", "Submit\nrequest", 890, 550, height: 110, enabled: false)])
]

func render(_ scene: Scene) -> CGImage {
    let width = 1280, height = 800
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(gray: scene.dark ? 0.10 : 0.97, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    func text(_ label: String, x: CGFloat, y: CGFloat, size: CGFloat, gray: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: 800 - y - size)
        CTLineDraw(line, context)
    }
    text(scene.title, x: 40, y: 26, size: 30, gray: scene.dark ? 0.95 : 0.12)
    for item in scene.controls {
        let r = CGRect(x: item.rect.minX, y: 800 - item.rect.maxY, width: item.rect.width, height: item.rect.height)
        context.setFillColor(gray: scene.dark ? 0.28 : 0.85, alpha: 1)
        context.addPath(CGPath(roundedRect: r, cornerWidth: 9, cornerHeight: 9, transform: nil)); context.fillPath()
        for (index, line) in item.visible.components(separatedBy: "\n").enumerated() {
            text(line, x: item.rect.minX + 20, y: item.rect.minY + 14 + CGFloat(index) * 34, size: 28, gray: item.enabled ? (scene.dark ? 1 : 0.05) : 0.55)
        }
    }
    return context.makeImage()!
}

@main struct Check {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            FileHandle.standardError.write(Data("Usage: visual-grounding-check APP_BUNDLE|--ocr-only NEW_OUTPUT_DIRECTORY\n".utf8))
            exit(2)
        }
        let ocrOnly = CommandLine.arguments[1] == "--ocr-only"
        let out = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: out.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let worker: GoClickWorker?
        if ocrOnly { worker = nil }
        else {
            let resources = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Contents/Resources")
            let config = try RuntimeConfiguration.resolve(JSONDecoder().decode([String: String].self, from: Data(contentsOf: resources.appendingPathComponent("VisionConfig.json"))), resources: resources)
            worker = GoClickWorker(configuration: config)
        }
        defer { worker?.shutdown() }
        func now() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
        let start = now()
        async let vision: Void? = worker?.warm()
        async let ocr: Void = ScreenObserver.warmTextRecognizer()
        _ = try await (vision, ocr)
        let cold = now() - start
        let frame = CGRect(x: -1280, y: 80, width: 1280, height: 800)
        var results = [[String: Any]]()
        for scene in scenes {
            let image = render(scene)
            let path = out.appendingPathComponent(scene.id + ".png")
            let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { fatalError("Could not save synthetic image") }
            let candidates = scene.controls.map { c in VisualTargetPolicy.Candidate(id: c.id, labels: c.labels, bounds: c.rect.offsetBy(dx: frame.minX, dy: frame.minY), enabled: c.enabled) }
            let started = now()
            let regions = try await ScreenObserver.textEvidence(image)
            let ocrMs = now() - started
            let augmented = VisualTextEvidence.augment(candidates, regions: regions, frame: frame)
            let eligible = VisualTargetPolicy.eligible(augmented, target: scene.target, frame: frame)
            let previousEligible = VisualTargetPolicy.eligible(candidates, target: scene.target, frame: frame).count
            var selected: String?, point: [Double] = [], prepareMs = 0.0, predictMs = 0.0
            if eligible.count == 1, let worker {
                let preparation = now()
                _ = try await worker.prepare(frameID: scene.id, image: image)
                prepareMs = now() - preparation
                let prediction = now()
                let reply = try await worker.predict(frameID: scene.id, target: scene.target)
                predictMs = now() - prediction
                point = reply.point ?? []
                selected = VisualTargetPolicy.select(point: point, candidates: augmented, target: scene.target, frame: frame)?.id
            } else if ocrOnly, eligible.count == 1 {
                selected = eligible[0].id
            }
            let row: [String: Any] = ["id": scene.id, "target": scene.target, "expected": scene.expected as Any? ?? NSNull(), "selected": selected as Any? ?? NSNull(), "correct": selected == scene.expected,
                                     "previousEligibleCount": previousEligible, "eligibleCount": eligible.count, "point": point,
                                     "ocrMs": ocrMs, "prepareRoundtripMs": prepareMs, "predictRoundtripMs": predictMs, "totalSelectionMs": now() - started,
                                     "augmentedLabels": augmented.map { ["id": $0.id, "labels": $0.labels] as [String: Any] },
                                     "recognized": regions.map { ["text": $0.text, "confidence": $0.confidence,
                                                                  "bounds": [$0.normalizedBounds.minX, $0.normalizedBounds.minY, $0.normalizedBounds.width, $0.normalizedBounds.height]] as [String: Any] }]
            results.append(row)
            print("\(scene.id): \(selected ?? "abstain") (\(selected == scene.expected ? "correct" : "miss"))")
            if selected != scene.expected {
                print("OCR evidence: \(regions.map(\.text)); labels: \(augmented.map(\.labels))")
            }
            await worker?.clear()
        }
        let report: [String: Any] = ["version": 2, "mode": ocrOnly ? "ocr-only" : "ocr-and-goclick",
                                    "scope": "Generated offline UI fixtures. No capture, AX discovery, speech, input delivery, live application outcome, or training. OCR-only mode checks label binding without loading GoClick; full mode also requires model-point agreement. Cold warmup separate. One sample per case.",
                                    "coldWarmupMs": cold, "cases": results]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("report.json"))
        if results.contains(where: { ($0["correct"] as? Bool) != true }) { exit(1) }
    }
}
