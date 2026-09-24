import Foundation

public enum NavigationEvidence {
    /// A changed document or origin alone cannot prove the intended destination.
    public static func matches(expected:String, observed:String?) -> Bool {
        guard let observed,let expectedURL=URL(string:expected),let observedURL=URL(string:observed),
              ["http","https"].contains(expectedURL.scheme ?? ""),expectedURL.host != nil,
              ["http","https"].contains(observedURL.scheme ?? ""),observedURL.host != nil else { return false }
        return expectedURL.absoluteString==observedURL.absoluteString
    }
}
