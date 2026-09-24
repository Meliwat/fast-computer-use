import Foundation

public enum VerificationOutcome: String, Codable, Sendable {
    case verified, unverified, failed
}

/// A dispatch acknowledgement alone cannot promote an action to verified.
public struct BrowserActionResult: Decodable, Sendable {
    public let ok: Bool
    public struct SearchTicket: Decodable, Sendable { public let token, documentId, targetId: String }
    public let nativeSearch: SearchTicket?
    public let armedToken: String?
    public let commandId: String?
    public let outcome: VerificationOutcome?
    public let message: String?
    public let error: String?
    public let totalMs: Double?
    public let expectedNavigationURL: String?
    public let xSearch: XSearchEvidence?
    public var summary: String {
        if !ok { return error ?? "Browser action failed" }
        if outcome == .verified { return message ?? "Action verified" }
        let detail = message ?? "Action delivered"
        return detail.localizedCaseInsensitiveContains("not verified") || detail.localizedCaseInsensitiveContains("no scroll") ? detail : "\(detail) · result not verified"
    }
}

public struct VisualFingerprint: Equatable, Sendable {
    public let samples: [UInt8]
    public init(samples: [UInt8]) { self.samples = samples }
    /// Pixel changes are evidence only; they never establish task completion.
    public func changedFraction(from other: Self, threshold: Int = 12) -> Double? {
        guard !samples.isEmpty, samples.count == other.samples.count else { return nil }
        let count = zip(samples, other.samples).filter { abs(Int($0.0) - Int($0.1)) > threshold }.count
        return Double(count) / Double(samples.count)
    }
}

public struct BrowserObservation: Codable, Sendable {
    public struct Bounds: Codable, Equatable, Sendable {
        public let x, y, width, height: Double
        public init(x:Double,y:Double,width:Double,height:Double) {self.x=x;self.y=y;self.width=width;self.height=height}
    }
    public struct Viewport: Codable, Sendable {
        public let width, height, scale: Double
        public init(width:Double,height:Double,scale:Double) {self.width=width;self.height=height;self.scale=scale}
    }
    public struct Candidate: Codable, Equatable, Sendable {
        public let id, role: String
        public let labels: [String]
        public let bounds: Bounds
        public let enabled, editable, clickable: Bool
        public let selected, expanded: String?
        public let navigationURL: String?
        public init(id:String,role:String,labels:[String],bounds:Bounds,enabled:Bool,editable:Bool,clickable:Bool,
                    selected:String?=nil,expanded:String?=nil,navigationURL:String?=nil) {
            self.id=id;self.role=role;self.labels=labels;self.bounds=bounds;self.enabled=enabled;self.editable=editable;self.clickable=clickable
            self.selected=selected;self.expanded=expanded;self.navigationURL=navigationURL
        }
    }
    public let version: Int
    public let documentId, observationId, origin: String
    public let url: String?
    public let capturedAt: Double
    public let revision: Int
    public let viewport: Viewport
    public let targetQuery: String?
    public let focusedId: String?
    public let truncated: Bool
    public let candidates: [Candidate]
    public init(documentId:String,observationId:String,origin:String,capturedAt:Double,viewport:Viewport,focusedId:String?,candidates:[Candidate]) {
        version=1;self.documentId=documentId;self.observationId=observationId;self.origin=origin;url=nil
        self.capturedAt=capturedAt;revision=0;self.viewport=viewport;targetQuery=nil;self.focusedId=focusedId;truncated=false;self.candidates=candidates
    }
}
public struct BrowserObservationReply: Decodable, Sendable {
    public let ok: Bool
    public let observation: BrowserObservation?
    public let error: String?
}

/// Negotiates behavior, not merely the on-disk extension version. A cached older
/// background worker can still call the unverified dispatcher in a newer script.
public struct BrowserCapabilities: Decodable, Sendable {
    public let ok: Bool
    public let error: String?
    public let protocolVersion: Int?
    public let verifiedDispatch: Bool?
    public let existingTextOperations: Bool?
    public let sequenceDispatch: Bool?
    public func requireSequenceDispatch() throws {
        try requireVerifiedDispatch()
        guard sequenceDispatch==true else {
            throw NSError(domain:"LocalVoiceBrowser",code:4,userInfo:[NSLocalizedDescriptionKey:"Reload Local Voice Browser in Chrome’s Extensions page for verified sequences; no action sent."])
        }
    }
    public func requireExistingText() throws {
        try requireVerifiedDispatch()
        guard existingTextOperations==true else {
            throw NSError(domain:"LocalVoiceBrowser",code:3,userInfo:[NSLocalizedDescriptionKey:"Reload Local Voice Browser in Chrome’s Extensions page to enable copying and changing existing text; no action sent."])
        }
    }
    public func requireVerifiedDispatch() throws {
        if !ok,let error,!error.localizedCaseInsensitiveContains("unsupported browser action") {
            throw NSError(domain:"LocalVoiceBrowser",code:1,userInfo:[NSLocalizedDescriptionKey:error])
        }
        guard ok, (protocolVersion ?? 0) >= 2, verifiedDispatch == true else {
            throw NSError(domain:"LocalVoiceBrowser",code:2,userInfo:[NSLocalizedDescriptionKey:
                "Reload Local Voice Browser in Chrome’s Extensions page, then try again. Its background dispatcher is out of date; no action sent."])
        }
    }
}
