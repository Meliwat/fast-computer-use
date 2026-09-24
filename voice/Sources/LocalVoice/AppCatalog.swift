import AppKit
import VoiceCore

/// Build once at launch, keeping filesystem scans out of command handling.
struct AppCatalog {
    let names: [String: String]
    init() {
        var candidates: [String: Set<String>] = [:]
        for (name, identifier) in Parser.defaultApps { candidates[name, default: []].insert(identifier) }
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory()+"/Applications"]
        for root in roots {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where file.hasSuffix(".app") {
                guard let bundle = Bundle(path: root+"/"+file), let identifier = bundle.bundleIdentifier else { continue }
                let labels = [String(file.dropLast(4)), bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, bundle.object(forInfoDictionaryKey: "CFBundleName") as? String].compactMap { $0 }
                for name in labels { candidates[name.lowercased(), default: []].insert(identifier) }
            }
        }
        names = candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
    }
    func resolve(_ name: String) -> String? { names[name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] }
}
