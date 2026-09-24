import Foundation
/// A pause ends an utterance only after speech and transcript have both settled.
public struct SpeechBoundary {
    private var text = ""
    private var changedAt: TimeInterval = 0
    public init() {}
    public mutating func update(_ text: String, now: TimeInterval) {
        if self.text != text { self.text = text; changedAt = now }
    }
    public func shouldFinish(now: TimeInterval, lastVoiceAt: TimeInterval) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && now - lastVoiceAt >= 0.85 && now - changedAt >= 0.55
    }
}
