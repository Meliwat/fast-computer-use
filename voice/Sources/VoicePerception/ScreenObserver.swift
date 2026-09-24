import AppKit
import ScreenCaptureKit
import Vision
import VoiceCore
import CryptoKit
import CoreText

/// Captures only during explicit commands, only if screen access already exists.
/// No permission prompts, frame logging, network calls, or UI input.
public final class ScreenObserver {
    private static let ocrQueue = DispatchQueue(label: "localvoice.ocr", qos: .userInitiated)
    public init() {}
    public struct Frame {
        public let id = UUID()
        public let capturedAt: TimeInterval
        public let app: String
        public let windowID: CGWindowID
        public let bounds: CGRect
        public let windowBounds: CGRect
        public let image: CGImage
        public let fingerprint: VisualFingerprint
        public let digest: String
    }
    public struct TextRegion {
        public let text: String
        public let bounds: CGRect // normalized Vision coordinates, bottom-left origin
        public let confidence: Float
    }
    public func capture(app: String) async throws -> Frame? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app else { return nil }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly:true)
        // CGWindowList is front-to-back; bind the frontmost ordinary window of
        // the foreground process instead of relying on ScreenCaptureKit order.
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]],
              let entry = ordered.first(where: {
                  ($0[kCGWindowOwnerPID as String] as? Int32) == pid &&
                  ($0[kCGWindowLayer as String] as? Int) == 0 &&
                  ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0
              }), let number = entry[kCGWindowNumber as String] as? UInt32,
              let window = content.windows.first(where: { $0.windowID == number }), let display = content.displays.max(by: { a,b in
            let ar = a.frame.intersection(window.frame), br = b.frame.intersection(window.frame)
            return ar.width * ar.height < br.width * br.height
        }) else { return nil }
        // Display capture preserves real occlusion. Remove only our own overlay.
        let overlays = content.windows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display:display,excludingWindows:overlays)
        let config = SCStreamConfiguration()
        config.width = display.width; config.height = display.height
        config.showsCursor = false; config.capturesAudio = false
        let full = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
        guard let current=Self.foregroundWindow(app:app),current.id==window.windowID,current.bounds==window.frame else { return nil }
        let visible = window.frame.intersection(display.frame)
        guard !visible.isNull, !visible.isEmpty else { return nil }
        let sx = Double(full.width)/display.frame.width, sy = Double(full.height)/display.frame.height
        let crop = CGRect(x:(visible.minX-display.frame.minX)*sx,y:(visible.minY-display.frame.minY)*sy,width:visible.width*sx,height:visible.height*sy)
        guard let image = full.cropping(to:crop) else { return nil }
        return Frame(capturedAt:ProcessInfo.processInfo.systemUptime,app:app,windowID:window.windowID,bounds:visible,windowBounds:window.frame,image:image,fingerprint:Self.fingerprint(image),digest:Self.digest(image))
    }
    public static func foregroundWindow(app: String) -> (id: CGWindowID, bounds: CGRect)? {
        guard let foreground=NSWorkspace.shared.frontmostApplication,foreground.bundleIdentifier==app,
              let entries=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]],
              let entry=entries.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32)==foreground.processIdentifier && ($0[kCGWindowLayer as String] as? Int)==0 && ($0[kCGWindowAlpha as String] as? Double ?? 1)>0 }),
              let id=entry[kCGWindowNumber as String] as? UInt32,
              let rect=entry[kCGWindowBounds as String] as? [String:Any],
              let bounds=CGRect(dictionaryRepresentation:rect as CFDictionary) else { return nil }
        return (id,bounds)
    }
    /// Canonical pixels, including tiny control changes; coarse fingerprints are diagnostics only.
    public static func digest(_ image: CGImage) -> String {
        let row=image.width*4
        guard let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:row,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),let buffer=context.data else { return "" }
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        return SHA256.hash(data:Data(bytes:buffer,count:row*image.height)).map { String(format:"%02x",$0) }.joined()
    }
    /// Exact target pixels plus a surrounding margin. This alone never approves
    /// input: the caller also re-observes labels, uniqueness and AX identity.
    public static func unchangedRegion(_ region: CGRect, frame: CGRect, before: CGImage, after: CGImage, padding: CGFloat = 12) -> Bool {
        let values=[region.minX,region.minY,region.width,region.height,frame.minX,frame.minY,frame.width,frame.height,padding]
        guard values.allSatisfy({$0.isFinite}),padding>=0,region.width>0,region.height>0,frame.width>0,frame.height>0,
              frame.contains(region),before.width==after.width,before.height==after.height else { return false }
        let expanded=region.insetBy(dx:-padding,dy:-padding).intersection(frame)
        let sx=CGFloat(before.width)/frame.width,sy=CGFloat(before.height)/frame.height
        let crop=CGRect(x:(expanded.minX-frame.minX)*sx,y:(expanded.minY-frame.minY)*sy,width:expanded.width*sx,height:expanded.height*sy).integral
        guard let first=before.cropping(to:crop),let second=after.cropping(to:crop) else { return false }
        let original=digest(first)
        return !original.isEmpty && original==digest(second)
    }
    public static func fingerprint(_ image: CGImage) -> VisualFingerprint {
        let size=64
        var bytes=[UInt8](repeating:0,count:size*size)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context=CGContext(data:buffer.baseAddress,width:size,height:size,bitsPerComponent:8,bytesPerRow:size,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .low
            context.draw(image,in:CGRect(x:0,y:0,width:size,height:size))
        }
        return VisualFingerprint(samples:bytes)
    }
    public static func recognize(_ image: CGImage, accurate: Bool = false) throws -> [TextRegion] {
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let best=observation.topCandidates(1).first else { return nil }
            return TextRegion(text:best.string,bounds:observation.boundingBox,confidence:best.confidence)
        }
    }
    /// CPU recognition runs outside the UI actor. Caller binds these results to
    /// the captured frame and rechecks its identity/pixels before dispatch.
    public static func textEvidence(_ image: CGImage) async throws -> [VisualTextEvidence.Region] {
        try await withCheckedThrowingContinuation { continuation in
            ocrQueue.async {
                do {
                    // On this OS the fast recognizer returns 0.5 for even clean
                    // text. Use accurate recognition for execution evidence;
                    // fast OCR remains available for read-only diagnostics.
                    let regions = try recognize(image, accurate: true).map {
                        VisualTextEvidence.Region(text: $0.text, normalizedBounds: $0.bounds, confidence: $0.confidence)
                    }
                    continuation.resume(returning: regions)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    /// Prime OCR using generated text, never a screenshot or microphone input.
    public static func warmTextRecognizer() async throws {
        guard let context = CGContext(data: nil, width: 300, height: 90, bitsPerComponent: 8, bytesPerRow: 1200,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 90))
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 32, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]
        context.textPosition = CGPoint(x: 20, y: 30)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Ready", attributes: attributes)), context)
        if let image = context.makeImage() { _ = try await textEvidence(image) }
    }
}
