import Foundation

/// A name selects one visible native field; its current text is never a label.
public enum NativeTextTarget {
    public struct Candidate {
        public let labels: [String]
        public let visible: Bool
        public let enabled: Bool
        public let secure: Bool
        public let writable: Bool
        public init(labels: [String], visible: Bool, enabled: Bool, secure: Bool, writable: Bool) {
            self.labels=labels; self.visible=visible; self.enabled=enabled; self.secure=secure; self.writable=writable
        }
    }
    public static func name(_ value: String) -> String {
        InteractionRules.normalizedLabel(value)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*:\s*$"#, with: "", options: .regularExpression)
    }
    public static func uniqueIndex(target: String, candidates: [Candidate], requireWritable:Bool=true) -> Int? {
        let raw=name(target)
        guard !raw.isEmpty else { return nil }
        let stripped=raw.replacingOccurrences(of: #"\s+(?:field|text box|input)$"#,with:"",options:.regularExpression)
        // Prefer the literal label before interpreting an optional role suffix.
        for wanted in raw==stripped ? [raw] : [raw,stripped] {
            let matches=candidates.indices.filter { candidates[$0].visible && candidates[$0].labels.contains(where:{name($0)==wanted}) }
            guard !matches.isEmpty else { continue }
            guard matches.count==1, let i=matches.first, candidates[i].enabled,
                  !candidates[i].secure, !requireWritable || candidates[i].writable else { return nil }
            return i
        }
        return nil
    }
}

/// One write, followed by bounded observation. A transient match is not success.
public struct NativeTextVerification {
    public enum Result: Equatable { case waiting, verified, failed }
    private let before: String
    private let expected: String
    private let start: TimeInterval
    private var last: TimeInterval
    private var matchedAt: TimeInterval?
    private var terminal: Result?
    public init(before: String, expected: String, startedAt: TimeInterval) {
        self.before=before; self.expected=expected; start=startedAt; last=startedAt
    }
    public mutating func observe(value: String?, sameContext: Bool, at now: TimeInterval) -> Result {
        if let terminal { return terminal }
        guard sameContext, now.isFinite, start.isFinite, now>=last, now-start<=0.5, let value else {
            terminal = .failed; return .failed
        }
        last=now
        if value==expected {
            if matchedAt==nil { matchedAt=now }
            if now-matchedAt!>=0.18 { terminal = .verified; return .verified }
        } else if matchedAt != nil || value != before {
            terminal = .failed; return .failed
        }
        return .waiting
    }
}
