import Foundation

/// Narrow X demo verifier. Visible result state is stronger than an Enter acknowledgement.
public struct XSearchEvidence:Decodable,Sendable {
    public let supported,queryMatches,loaded:Bool
    public let signature,documentId:String
    public let visibleResults:Int
    public var ready:Bool { supported && queryMatches && loaded && visibleResults>0 && !signature.isEmpty && !documentId.isEmpty }
    public func verifies(after before:XSearchEvidence)->Bool {
        ready && before.supported && (documentId != before.documentId || signature != before.signature)
    }
}
