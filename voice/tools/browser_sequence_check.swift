// Offline test adapter. No app lifecycle, accessibility, speech or network access.
// The fixture process supplies observations and action replies over standard I/O.
import Foundation
import VoiceCore

@main struct SequenceCheck {
    @MainActor static func main() async {
        var clock=0.0
        func emit(_ value:[String:Any]) throws {
            var data=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]);data.append(10)
            try FileHandle.standardOutput.write(contentsOf:data)
        }
        func reply(_ request:[String:Any]) throws -> Data {
            try emit(request)
            guard let line=readLine(),let data=line.data(using:.utf8),
                  let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw NSError(domain:"Fixture",code:1) }
            if let now=object["clock"] as? Double {clock=now}
            return data
        }
        do {
            guard let text=readLine(),let plan=try BrowserSequence.plan(text) else {
                try emit(["kind":"done","verified":0,"error":"Not a browser sequence"]);return
            }
            let count=try await BrowserSequence.run(plan,preflight:{texts,required in
                let data=try reply(["kind":"preflight","texts":texts,"requiredOperations":required.map {$0 as Any? ?? NSNull()}])
                return (try JSONSerialization.jsonObject(with:data) as? [String:Any])?["accepted"] as? Bool == true
            },stillValid:{true},observe:{target in
                let data=try reply(["kind":"observe","target":target as Any? ?? NSNull()])
                let value=try JSONDecoder().decode(BrowserObservationReply.self,from:data)
                guard value.ok,let observation=value.observation else {throw NSError(domain:"Fixture",code:2,userInfo:[NSLocalizedDescriptionKey:value.error ?? "Observation failed"])}
                return observation
            },propose:{text,observation in
                let data=try reply(["kind":"propose","text":text,"observation":try JSONSerialization.jsonObject(with:JSONEncoder().encode(observation))])
                return try JSONDecoder().decode(GroundedProposal.self,from:data).validatedCommand(for:observation,requestID:"fixture",nowMs:clock)
            },dispatch:{command,_ in
                let data=try reply(["kind":"dispatch","command":try JSONSerialization.jsonObject(with:JSONEncoder().encode(command))])
                let value=try JSONDecoder().decode(BrowserActionResult.self,from:data)
                return value.ok && value.outcome == .verified
            },nowMs:{clock})
            try emit(["kind":"done","verified":count])
        } catch {try? emit(["kind":"done","error":error.localizedDescription])}
    }
}
