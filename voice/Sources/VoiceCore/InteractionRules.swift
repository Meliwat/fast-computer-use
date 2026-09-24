import Foundation
public enum InteractionRules {
    /// UTF-16 ranges match macOS accessibility ranges, including emoji and accents.
    public static func inserting(_ text: String, into original: String, selection: NSRange) -> String? {
        let source = original as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
              selection.location <= source.length, selection.length <= source.length - selection.location else { return nil }
        return source.replacingCharacters(in: selection, with: text)
    }
    public static func normalizedLabel(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    public static let sendLabels = Set(["send", "send message", "send prompt", "submit prompt"])
    public static func matchingIndices(labels: [[String]], enabled: [Bool], wanted: Set<String>) -> [Int] {
        labels.indices.filter { index in
            index < enabled.count && enabled[index] && !Set(labels[index].map(normalizedLabel)).isDisjoint(with: wanted)
        }
    }
    public static let blockedTypingApps: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"]
}

public struct AppContext {
    public private(set) var app: String?
    public init() {}
    public mutating func observeForeground(_ identifier: String?) {
        guard let identifier, identifier != "dev.localvoice.prototype" else { return }
        app = identifier
    }
    public mutating func activated(_ identifier: String) { app = identifier }
}
