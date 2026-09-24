import Foundation

/// Relative worker/model paths resolve inside the signed bundle after it is moved.
/// Absolute interpreter paths refer to the separately installed local runtime.
public enum RuntimeConfiguration {
    public static func resolve(_ config:[String:String],resources:URL) throws -> [String:String] {
        var resolved=config
        let root=resources.standardizedFileURL
        for key in ["python","worker","model","models"] {
            guard let value=config[key] else { continue }
            guard !value.isEmpty else { throw invalid("Empty runtime path: \(key)") }
            if (value as NSString).isAbsolutePath { continue }
            let path=root.appendingPathComponent(value).standardizedFileURL
            guard path.path.hasPrefix(root.path+"/") else { throw invalid("Runtime path leaves the app bundle") }
            resolved[key]=path.path
        }
        return resolved
    }
    private static func invalid(_ message:String)->NSError { NSError(domain:"RuntimeConfiguration",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
}
