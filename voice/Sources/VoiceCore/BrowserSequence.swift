import Foundation

/// One route for exact and learned browser sequences. Exact operations need no model;
/// targets are bound against fresh state only when their turn arrives.
public enum BrowserSequence {
    public struct Step: Sendable {
        public let text: String
        public var command: BrowserCommand?
        public var requiresFocus: Bool
    }
    public struct Plan: Sendable {
        public let steps: [Step]
        public var preflightTexts: [String] { steps.filter {$0.command==nil}.map(\.text) }
        public var requiredOperations: [String?] { steps.filter {$0.command==nil}.map {$0.requiresFocus ? "focus":nil} }
    }
    private static func failure(_ message:String)->NSError {
        NSError(domain:"BrowserSequence",code:1,userInfo:[NSLocalizedDescriptionKey:message])
    }
    public static func plan(_ text:String,apps:[String:String]=Parser.defaultApps) throws -> Plan? {
        let parsed=Parser.parse(text,apps:apps,browserContext:true)
        // The ordinary parser owns literal tails and its explicit “and” sequences.
        let clauses:[String]
        if parsed.count>1 { clauses=Parser.parts(text) }
        else if let explicit=try GroundedSequence.clauses(text) { clauses=explicit }
        else { return nil }
        // App-launch sequences may already have dispatched their stable open-app prefix.
        // Leave those to the app router; never reinterpret or replay that prefix here.
        for clause in clauses {
            if let command=Parser.parse(clause,apps:apps,browserContext:true).first,
               ![Action.clickControl,.typeText,.browserAction,.sendDraft].contains(command.action) { return nil }
        }
        return try plan(clauses:clauses,apps:apps)
    }
    public static func plan(clauses:[String],apps:[String:String]=Parser.defaultApps) throws -> Plan {
        guard (2...3).contains(clauses.count),clauses.allSatisfy({!$0.isEmpty}) else { throw failure("Use two or three complete browser commands") }
        var steps:[Step]=[]
        for (index,clause) in clauses.enumerated() {
            let parsed=Parser.parse(clause,apps:apps,browserContext:true)
            var command:BrowserCommand?,focus=false
            if parsed.count==1,let exact=parsed.first {
                switch exact.action {
                case .clickControl: command=BrowserCommand(op:"click",target:exact.value)
                case .typeText: command=BrowserCommand(op:"type",value:exact.value)
                case .browserAction: command=try BrowserCommand.decode(exact.value)
                default: throw failure("Use that operation in a separate utterance")
                }
                guard let command,["click","type","fill","select","check","scroll","copyText","changeCase"].contains(command.op) else { throw failure("Use search, submission and tab changes in separate utterances") }
            } else if parsed.isEmpty {
                let native=Parser.parse(clause,apps:apps)
                if native.count==1,native[0].action == .focusControl {
                    command=BrowserCommand(op:"click",target:native[0].value);focus=true
                } else {
                    guard !Parser.hasDictation(clause) else { throw failure("Use ‘focus … then type …’ or ‘fill … with …’") }
                }
            } else { throw failure("Each sequence step must contain one operation") }
            if let command,["type","fill"].contains(command.op) {
                guard index==clauses.count-1,index>0,let value=command.value,!value.isEmpty,value.utf16.count<=16000 else { throw failure("Put literal typing or filling last, with 1–16000 characters") }
                if command.op=="type" {
                    guard steps.last?.command==nil || steps.last?.command?.op=="click" else { throw failure("Focus a field before typing") }
                    steps[steps.count-1].requiresFocus=true
                }
            }
            steps.append(Step(text:clause,command:command,requiresFocus:focus))
        }
        return Plan(steps:steps)
    }
    private static func validate(_ observation:BrowserObservation,nowMs:Double,complete:Bool=true) throws {
        guard observation.version==1,(!complete || !observation.truncated),observation.candidates.count<=48,
              !observation.documentId.isEmpty,!observation.observationId.isEmpty,
              nowMs.isFinite,observation.capturedAt.isFinite,(-250...2000).contains(nowMs-observation.capturedAt) else { throw failure("Page observation expired or incomplete; no action sent") }
    }
    private static func bind(_ step:Step,observation:BrowserObservation,focus:BrowserCommand?,nowMs:Double) throws -> BrowserCommand {
        guard var command=step.command else { throw failure("Missing exact command") }
        if command.op=="type" {
            guard let focus else { throw failure("Focus a field before typing; no text sent") }
            return try GroundedSequence.bindType(command.value ?? "",after:focus,observation:observation,nowMs:nowMs)
        }
        if let target=command.target,["click","fill","select","check"].contains(command.op) {
            guard observation.targetQuery==target else { throw failure("Observation did not match the requested target") }
            let matches=observation.candidates.filter { candidate in
                guard candidate.enabled else { return false }
                switch command.op {
                case "fill": return candidate.editable && candidate.clickable
                case "select": return candidate.role=="select"
                case "check": return ["checkbox","switch","menuitemcheckbox"].contains(candidate.role)
                default: return candidate.clickable && (!step.requiresFocus || candidate.editable)
                }
            }
            guard matches.count==1 else { throw failure("Couldn’t identify one available control; name its field, button or section") }
            command.targetId=matches[0].id
        }
        command.documentId=observation.documentId
        // Existing-text operations bind both named fields inside their own dispatcher.
        if !["copyText","changeCase"].contains(command.op) { command.observationId=observation.observationId }
        return command
    }
    @MainActor public static func run(_ plan:Plan,
        preflight:([String],[String?]) async throws -> Bool,stillValid:()->Bool,
        observe:(String?) async throws -> BrowserObservation,
        propose:(String,BrowserObservation) async throws -> BrowserCommand?,
        dispatch:(BrowserCommand,BrowserObservation) async throws -> Bool,
        nowMs:()->Double = {Date().timeIntervalSince1970*1000}) async throws -> Int {
        var expectedDocument:String?,expectedURL:String?,focus:BrowserCommand?
        var index=0
        return try await GroundedSequence.run(plan.steps.map(\.text),preflight:{_ in
            plan.preflightTexts.isEmpty ? true : try await preflight(plan.preflightTexts,plan.requiredOperations)
        },stillValid:stillValid,step:{_ in
            let step=plan.steps[index];index+=1
            let query=step.command.flatMap { $0.op=="type" ? focus?.target : (["click","fill","select","check"].contains($0.op) ? $0.target:nil) }
            let complete = !["scroll","copyText","changeCase"].contains(step.command?.op ?? "")
            let observation=try await observe(query)
            try validate(observation,nowMs:nowMs(),complete:complete)
            if let expectedDocument,observation.documentId != expectedDocument { throw failure("Page changed between steps") }
            if let expectedURL,observation.url != expectedURL { throw failure("Page changed between steps") }
            guard stillValid() else { throw failure("Sequence cancelled before resolving the next target") }
            let command:BrowserCommand
            if step.command != nil { command=try bind(step,observation:observation,focus:focus,nowMs:nowMs()) }
            else {
                guard let proposed=try await propose(step.text,observation),proposed.op=="click",
                      proposed.documentId==observation.documentId,proposed.observationId==observation.observationId,
                      let target=proposed.targetId,observation.candidates.filter({$0.id==target && $0.enabled && $0.clickable && (!step.requiresFocus || $0.editable)}).count==1 else { throw failure("Couldn’t identify one available control") }
                command=proposed
            }
            try validate(observation,nowMs:nowMs(),complete:complete)
            guard stillValid() else { throw failure("Sequence cancelled before dispatch") }
            guard try await dispatch(command,observation) else { return false }
            guard stillValid() else { throw failure("Sequence cancelled after dispatch") }
            let after=try await observe(nil)
            try validate(after,nowMs:nowMs(),complete:false)
            let target=observation.candidates.first {$0.id==command.targetId}
            if let destination=command.op=="click" ? target?.navigationURL:nil {
                guard NavigationEvidence.matches(expected:destination,observed:after.url) else { throw failure("Destination changed after verification") }
            } else {
                guard after.documentId==observation.documentId,after.url==observation.url else { throw failure("Page changed after verification") }
            }
            let focused=command.op=="click" && target?.editable==true
            if focused,after.focusedId != command.targetId { throw failure("Field lost focus after verification") }
            focus=focused ? command:nil
            expectedDocument=after.documentId;expectedURL=after.url
            return true
        })
    }
}
