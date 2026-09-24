import Foundation
import CoreGraphics

/// A strict, independently inspectable gate. This is not a trained confidence model.
public enum VisualTargetPolicy {
    public struct Candidate: Equatable, Sendable {
        public let id: String
        public let labels: [String]
        public let bounds: CGRect
        public let enabled: Bool
        public init(id: String, labels: [String], bounds: CGRect, enabled: Bool = true) {
            self.id = id; self.labels = labels; self.bounds = bounds; self.enabled = enabled
        }
    }
    private static let filler: Set<String> = ["the","a","an","button","icon","control","link","please","click","press","tap","on","at","in","label","labeled","labelled"]
    private static let spatial: Set<String> = ["top","bottom","left","right","upper","lower"]
    private static func tokens(_ text: String) -> Set<String> {
        Set(text.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"))
            .lowercased().components(separatedBy:CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }
    public static func eligible(_ candidates: [Candidate], target: String, frame: CGRect) -> [Candidate] {
        let words = tokens(target), content = words.subtracting(filler).subtracting(spatial)
        guard !content.isEmpty, frame.width > 0, frame.height > 0 else { return [] }
        return candidates.filter { candidate in
            guard candidate.enabled, candidate.bounds.width > 0, candidate.bounds.height > 0,
                  frame.contains(candidate.bounds), candidate.labels.contains(where: { content.isSubset(of:tokens($0)) }) else { return false }
            let x=(candidate.bounds.midX-frame.minX)/frame.width, y=(candidate.bounds.midY-frame.minY)/frame.height
            if !words.isDisjoint(with:["top","upper"]) && y >= 0.5 { return false }
            if !words.isDisjoint(with:["bottom","lower"]) && y <= 0.5 { return false }
            if words.contains("left") && x >= 0.5 { return false }
            if words.contains("right") && x <= 0.5 { return false }
            return true
        }
    }
    public static func select(point: [Double], candidates: [Candidate], target: String, frame: CGRect) -> Candidate? {
        guard point.count == 2, point.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let eligible = eligible(candidates,target:target,frame:frame)
        // A model coordinate cannot resolve an unspecified duplicate name.
        guard eligible.count == 1 else { return nil }
        let location=CGPoint(x:frame.minX+point[0]*frame.width,y:frame.minY+point[1]*frame.height)
        guard eligible[0].bounds.contains(location),
              candidates.filter({ $0.enabled && $0.bounds.contains(location) }).count == 1 else { return nil }
        return eligible[0]
    }
    public static func fresh(capturedAt: TimeInterval, now: TimeInterval, originalDigest: String, currentDigest: String,
                             originalWindow: UInt32, currentWindow: UInt32, originalBounds: CGRect, currentBounds: CGRect) -> Bool {
        !originalDigest.isEmpty && originalDigest == currentDigest && sameSurface(capturedAt:capturedAt,now:now,originalWindow:originalWindow,currentWindow:currentWindow,originalBounds:originalBounds,currentBounds:currentBounds)
    }
    public static func sameSurface(capturedAt: TimeInterval, now: TimeInterval, originalWindow: UInt32, currentWindow: UInt32, originalBounds: CGRect, currentBounds: CGRect) -> Bool {
        now >= capturedAt && now-capturedAt <= 15 &&
        originalWindow == currentWindow && originalBounds == currentBounds
    }
}
