import Foundation
public enum WebDestination {
    public static let names = ["github":"https://github.com", "git hub":"https://github.com", "youtube":"https://www.youtube.com", "you tube":"https://www.youtube.com", "google":"https://www.google.com", "gmail":"https://mail.google.com", "reddit":"https://www.reddit.com", "wikipedia":"https://www.wikipedia.org", "chatgpt":"https://chatgpt.com", "chat gpt":"https://chatgpt.com", "x":"https://x.com", "twitter":"https://x.com", "hacker news":"https://news.ycombinator.com"]
    private static let separators: [(NSRegularExpression,String)] = [
        (#"\s+dot\s+"#, "."), (#"\s+slash\s+"#, "/"), (#"\s+(?:dash|hyphen)\s+"#, "-"), (#"\s+underscore\s+"#, "_")
    ].map { (try! NSRegularExpression(pattern: $0.0, options: .caseInsensitive), $0.1) }
    public static func resolve(_ spoken: String) -> String? {
        var text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        if let named = names[text.lowercased()] { return named }
        for (regex, replacement) in separators { text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement) }
        guard !text.contains(where: { $0.isWhitespace }), !text.contains("\\") else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text), ["https","http"].contains(components.scheme?.lowercased() ?? ""),
              components.user == nil, components.password == nil, let host = components.host,
              host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."), !host.contains(".."),
              components.url != nil else { return nil }
        components.host = host.lowercased(); components.scheme = components.scheme?.lowercased()
        return components.url?.absoluteString
    }
}
/// Fixed local routes. No model-generated deep links or arbitrary scripts.
public enum AppActionRoute {
    public static func chatURL(for app: String) -> URL? {
        app == "com.openai.codex" ? URL(string: "codex://threads/new") : nil
    }
    public static let tabApps = Set(["com.apple.Safari", "com.google.Chrome"])
    public static let documentApps = Set(["com.apple.TextEdit"])
}
