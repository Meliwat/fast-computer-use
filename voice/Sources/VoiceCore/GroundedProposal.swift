import Foundation

/// The language worker proposes an identity-bound click/focus, never arbitrary browser input.
public struct GroundedProposal: Decodable, Sendable {
    public struct Operation: Decodable, Sendable { public let operation: String; public let confidence: Double }
    public let id: String?
    public let command: BrowserCommand?
    public let reason: String?
    public let operation: Operation?
    public let source: String?
    public let milliseconds: Double?
    public let error: String?
    public func validatedCommand(for observation: BrowserObservation, requestID: String, nowMs: Double) throws -> BrowserCommand? {
        func invalid(_ message: String) -> NSError { NSError(domain:"GroundedCommand",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        if let error { throw invalid("Local grounding worker: \(error)") }
        guard id==requestID else { throw invalid("Local grounding reply did not match this request") }
        guard let command else { return nil }
        guard observation.version==1, !observation.truncated, observation.candidates.count<=48,
              nowMs.isFinite, observation.capturedAt.isFinite,
              nowMs-observation.capturedAt >= -250, nowMs-observation.capturedAt <= 2000 else { throw invalid("Page observation expired or incomplete; try again") }
        guard command.op=="click", command.target==nil, command.value==nil, command.checked==nil, command.token==nil,
              command.documentId==observation.documentId, command.observationId==observation.observationId,
              let targetID=command.targetId, let operation,
              ["activate","focus"].contains(operation.operation), operation.confidence.isFinite, operation.confidence>=0.99 else { throw invalid("Local grounding returned an invalid action") }
        let matches=observation.candidates.filter {$0.id==targetID}
        guard matches.count==1, let target=matches.first, target.enabled, target.clickable,
              target.editable == (operation.operation=="focus") else { throw invalid("Selected control is unavailable or has a different role") }
        return command
    }
}
