import Foundation

/// Explicit, bounded sequences. Every operation is checked before the first action;
/// each subsequent target is resolved only after the preceding action is verified.
public enum GroundedSequence {
    private static func failure(_ message:String)->NSError {
        NSError(domain:"GroundedSequence",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }
    public static func clauses(_ text:String) throws -> [String]? {
        let regex=try NSRegularExpression(pattern:#"\b(?:and\s+)?then\b"#,options:.caseInsensitive)
        var remaining=text.trimmingCharacters(in:.whitespacesAndNewlines),parts:[String]=[]
        while true {
            // Once dictation starts, every remaining word is literal data, including “then”.
            if try textCommand(remaining) != nil {
                if parts.isEmpty { return nil }
                parts.append(remaining);break
            }
            guard let match=regex.firstMatch(in:remaining,range:NSRange(remaining.startIndex...,in:remaining)),let range=Range(match.range,in:remaining) else {
                if parts.isEmpty { return nil }
                parts.append(remaining.trimmingCharacters(in:.whitespacesAndNewlines.union(CharacterSet(charactersIn:",;.!?"))));break
            }
            parts.append(String(remaining[..<range.lowerBound]).trimmingCharacters(in:.whitespacesAndNewlines.union(CharacterSet(charactersIn:",;.!?"))))
            remaining=String(remaining[range.upperBound...]).trimmingCharacters(in:.whitespacesAndNewlines)
            if parts.count>=3 { throw failure("Use at most three commands before the literal text") }
        }
        guard (2...3).contains(parts.count),parts.allSatisfy({ !$0.isEmpty }) else {
            throw failure("Use two or three complete commands joined by ‘then’")
        }
        return parts
    }
    public static func textCommand(_ clause:String) throws -> BrowserCommand? {
        let commands=Parser.parse(clause,browserContext:true)
        guard commands.count==1,let command=commands.first else { return nil }
        var textCommand:BrowserCommand?
        if command.action == .typeText { textCommand=BrowserCommand(op:"type",value:command.value) }
        if command.action == .browserAction {
            let browser=try BrowserCommand.decode(command.value)
            if browser.op=="fill" { textCommand=browser }
        }
        if let value=textCommand?.value, value.isEmpty || value.utf16.count>16000 { throw failure("Text must contain between 1 and 16000 characters") }
        return textCommand
    }
    public static func preflightPlan(_ clauses:[String]) throws -> (texts:[String],requiredOperations:[String?]) {
        var texts:[String]=[],required:[String?]=[]
        for (index,clause) in clauses.enumerated() {
            if let text=try textCommand(clause) {
                guard index==clauses.count-1,index>0 else { throw failure("Put literal typing or filling last") }
                if text.op=="fill",let target=text.target {
                    texts.append("Focus \(target)");required.append("focus")
                } else {
                    guard !texts.isEmpty else { throw failure("Focus a field before typing") }
                    required[required.count-1]="focus"
                }
            } else {
                guard !Parser.hasDictation(clause) else { throw failure("In a sequence, use ‘focus … then type …’ or ‘fill … with …’; submit searches separately") }
                texts.append(clause);required.append(nil)
            }
        }
        return (texts,required)
    }
    public static func bindType(_ text:String,after focus:BrowserCommand,observation:BrowserObservation,nowMs:Double) throws -> BrowserCommand {
        guard observation.version==1,!observation.truncated,observation.candidates.count<=48,
              nowMs.isFinite,observation.capturedAt.isFinite,(-250...2000).contains(nowMs-observation.capturedAt),
              observation.documentId==focus.documentId,let target=focus.targetId,observation.focusedId==target else { throw failure("The verified field lost focus or the page changed; no text sent") }
        let matches=observation.candidates.filter {$0.id==target}
        guard matches.count==1,let field=matches.first,field.enabled,field.editable,field.clickable else { throw failure("The verified text field is no longer available") }
        return BrowserCommand(op:"type",value:text,targetId:target,documentId:observation.documentId,observationId:observation.observationId)
    }
    @MainActor public static func run(_ clauses:[String], preflight:([String]) async throws -> Bool,
        stillValid:()->Bool, step:(String) async throws -> Bool) async throws -> Int {
        guard (2...3).contains(clauses.count),clauses.allSatisfy({ !$0.isEmpty }),stillValid() else { throw failure("Sequence cancelled or invalid") }
        guard try await preflight(clauses) else { throw failure("Sequence contains an unsupported or uncertain operation; no actions sent") }
        var completed=0
        for (index,clause) in clauses.enumerated() {
            guard stillValid() else { throw failure("Sequence cancelled after \(completed) verified steps") }
            do {
                guard try await step(clause) else { throw failure("Action result could not be verified; it will not be repeated") }
                completed+=1
            } catch { throw failure("Stopped at step \(index+1) (\(completed) verified): \(error.localizedDescription)") }
        }
        return completed
    }
}

public struct GroundedPreflight:Decodable,Sendable {
    public let id:String?
    public let operations:[GroundedProposal.Operation]?
    public let error:String?
    public func accepts(requestID:String,count:Int,requiredOperations:[String?]?=nil)->Bool {
        guard error==nil,id==requestID,let operations,operations.count==count,(1...3).contains(count) else { return false }
        if let requiredOperations {
            guard requiredOperations.count==count else { return false }
            for (operation,required) in zip(operations,requiredOperations) {
                if let required,operation.operation != required { return false }
            }
        }
        return operations.allSatisfy { ["activate","focus"].contains($0.operation) && $0.confidence.isFinite && $0.confidence>=0.99 }
    }
}
