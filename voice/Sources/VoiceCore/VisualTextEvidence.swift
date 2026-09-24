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

    private struct Line {
        let text: String
        let bounds: CGRect
    }

    private static func wrappedLabel(_ lines: [Line]) -> String? {
        let ordered = lines.sorted {
            $0.bounds.minY == $1.bounds.minY ? $0.bounds.minX < $1.bounds.minX : $0.bounds.minY < $1.bounds.minY
        }
        guard !ordered.isEmpty else { return nil }
        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            let a = previous.bounds, b = current.bounds
            let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
            // Wrapped lines form one nearby vertical stack. Overlapping rows,
            // separate columns and distant captions do not form one label.
            guard b.minY >= a.maxY, b.minY - a.maxY <= max(a.height, b.height),
                  overlap >= min(a.width, b.width) * 0.5 else { return nil }
        }
        let label = ordered.map(\.text).joined(separator: " ")
        return label.count <= 300 ? label : nil
    }

    public static func augment(_ candidates: [VisualTargetPolicy.Candidate], regions: [Region], frame: CGRect) -> [VisualTargetPolicy.Candidate] {
        guard valid(frame) else { return candidates }
        var evidence = [String: [Line]]()
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
            evidence[owner.id, default: []].append(Line(text: label, bounds: bounds))
        }
        return candidates.map { candidate in
            guard let lines = evidence[candidate.id], let label = wrappedLabel(lines) else { return candidate }
            return .init(id: candidate.id, labels: [label], bounds: candidate.bounds, enabled: candidate.enabled)
        }
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy { $0.isFinite } && rect.width > 0 && rect.height > 0
    }
}
