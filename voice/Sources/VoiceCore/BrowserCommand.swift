import Foundation
public struct BrowserCommand: Codable, Equatable, Sendable {
    public let op: String
    public var target: String? = nil
    public var value: String? = nil
    public var source: String? = nil
    public var checked: Bool? = nil
    public var targetId: String? = nil
    public var documentId: String? = nil
    public var token: String? = nil
    public var observationId: String? = nil
    public init(op: String, target: String? = nil, value: String? = nil, source: String? = nil, checked: Bool? = nil, targetId: String? = nil, documentId: String? = nil, observationId: String? = nil, token: String? = nil) {
        self.token = token; self.op = op; self.target = target; self.value = value; self.checked = checked
        self.targetId = targetId; self.documentId = documentId; self.observationId = observationId
        self.source=source
    }
    public var command: Command {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Command(.browserAction, String(data:try! encoder.encode(self),encoding:.utf8)!)
    }
    public static func decode(_ value: String) throws -> BrowserCommand { try JSONDecoder().decode(Self.self,from:Data(value.utf8)) }
}
