import Foundation
import CoreGraphics

/// Associates visible text with an existing actionable control; OCR alone does
/// not invent a click target or authorize a coordinate. Evidence is frame-local.
public enum VisualTextEvidence {
    public struct Region: Sendable {
        public let text: String
        /// Vision's normalized, bottom-left-origin coordinates.
        public let normalizedBounds: CGRect
        public let confidence: Float
        public init(text: String, normalizedBounds: CGRect, confidence: Float) {
            self.text = text; self.normalizedBounds = normalizedBounds; self.confidence = confidence
        }
    }

    public static func augment(_ candidates: [VisualTargetPolicy.Candidate], regions: [Region], frame: CGRect) -> [VisualTargetPolicy.Candidate] {
        guard valid(frame) else { return candidates }
        var evidence = [String: [String]]()
        for region in regions {
            let label = region.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let box = region.normalizedBounds
            guard region.confidence.isFinite, region.confidence >= 0.8, !label.isEmpty, label.count <= 300,
                  valid(box), CGRect(x: 0, y: 0, width: 1, height: 1).contains(box) else { continue }
            // Frame coordinates are desktop points, independent of capture scale.
            let bounds = CGRect(x: frame.minX + box.minX * frame.width,
                                y: frame.minY + (1 - box.maxY) * frame.height,
                                width: box.width * frame.width, height: box.height * frame.height)
            // Include disabled and overlapping controls in ownership checks.
            // Even partial intersection makes attachment uncertain.
            let owners = candidates.filter { $0.bounds.intersects(bounds) }
            guard owners.count == 1, let owner = owners.first, owner.enabled,
                  frame.contains(owner.bounds), owner.bounds.contains(bounds),
                  owner.labels.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { continue }
            evidence[owner.id, default: []].append(label)
        }
        return candidates.map { candidate in
            guard let labels = evidence[candidate.id], labels.count == 1 else { return candidate }
            return .init(id: candidate.id, labels: labels, bounds: candidate.bounds, enabled: candidate.enabled)
        }
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy { $0.isFinite } && rect.width > 0 && rect.height > 0
    }
}
