import Foundation

/// Values come from an observed field, never from generated replacement text.
public struct ExistingTextOperation: Equatable, Sendable {
    public enum Kind: String, Sendable { case copy, uppercase, lowercase }
    public let kind: Kind
    public let source: String
    public let target: String
    public init(command: BrowserCommand) throws {
        guard let target=command.target,Self.validName(target) else { throw Self.failure("Name the destination field") }
        self.target=target
        switch command.op {
        case "copyText":
            guard let source=command.source,Self.validName(source),command.value==nil else { throw Self.failure("Name the source and destination fields") }
            kind = .copy;self.source=source
        case "changeCase":
            guard let kind=Kind(rawValue:command.value ?? ""),kind != .copy,command.source==nil else { throw Self.failure("Choose uppercase or lowercase") }
            self.kind=kind;source=target
        default: throw Self.failure("Unsupported existing-text operation")
        }
    }
    public func applying(to text:String) throws -> String {
        guard text.utf16.count<=16000 else { throw Self.failure("The source field is too long") }
        let result: String
        switch kind {
        case .copy:result=text
        case .uppercase:result=text.uppercased()
        case .lowercase:result=text.lowercased()
        }
        guard result.utf16.count<=16000 else { throw Self.failure("The resulting text is too long") }
        return result
    }
    private static func validName(_ name:String)->Bool {
        !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.utf16.count<=100 &&
        name.rangeOfCharacter(from:.controlCharacters)==nil
    }
    private static func failure(_ message:String)->NSError { NSError(domain:"ExistingText",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
}
