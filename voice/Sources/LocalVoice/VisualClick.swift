import AppKit
import VoiceCore
import VoicePerception

/// Captures/encodes only during a user utterance or an explicit visual command.
/// Weights stay resident; a single ephemeral image expires after the utterance.
@MainActor final class VisualClick {
    private let worker=GoClickWorker()
    private let observer=ScreenObserver()
    private struct PreparedFrame {
        let frame: ScreenObserver.Frame
        let text: [VisualTextEvidence.Region]
    }
    private var prefetch: Task<PreparedFrame?,Never>?
    private var expiry: Task<Void,Never>?
    private var epoch=UUID()
    func warm() async throws {
        async let model: Void = worker.warm()
        async let text: Void = ScreenObserver.warmTextRecognizer()
        _ = try await (model,text)
    }
    func begin(app: String?) {
        invalidate()
        guard let app else { return }
        let token=epoch
        prefetch=Task {
            do {
                guard let frame=try await observer.capture(app:app),!Task.isCancelled,epoch==token else { return nil }
                async let text=ScreenObserver.textEvidence(frame.image)
                _ = try await worker.prepare(frameID:frame.id.uuidString,image:frame.image)
                let recognized=try await text
                guard !Task.isCancelled,epoch==token else { return nil }
                return PreparedFrame(frame:frame,text:recognized)
            } catch { return nil }
        }
        expiry=Task {
            try? await Task.sleep(nanoseconds:15_000_000_000)
            guard !Task.isCancelled,epoch==token else { return }
            invalidate()
        }
    }
    func invalidate() {
        epoch=UUID();prefetch?.cancel();prefetch=nil;expiry?.cancel();expiry=nil
        Task { await worker.clear() }
    }
    func shutdown() { invalidate();worker.shutdown() }
    private func fail(_ text: String) -> NSError { NSError(domain:"LocalVoiceVisualClick",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    private func sameSurface(_ original:ScreenObserver.Frame,_ current:ScreenObserver.Frame) -> Bool {
        original.windowBounds==current.windowBounds && VisualTargetPolicy.sameSurface(capturedAt:original.capturedAt,now:ProcessInfo.processInfo.systemUptime,originalWindow:original.windowID,currentWindow:current.windowID,originalBounds:original.bounds,currentBounds:current.bounds)
    }
    private func unnamed(_ candidates:[VisualTargetPolicy.Candidate]) -> Bool {
        candidates.contains(where: { $0.enabled && $0.labels.allSatisfy { $0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty } })
    }
    func click(_ target: String, app: String, interaction: AppInteraction, stillValid: () -> Bool) async throws -> String {
        let token=epoch
        let cached=await prefetch?.value
        guard stillValid(),epoch==token else { throw fail("Cancelled before visual selection") }
        // Refresh at command completion; never predict from a frame merely because it is cached.
        guard let frame=try await observer.capture(app:app) else { throw fail("Visual targeting needs Local Voice Screen Recording access and a focused window") }
        let snapshot=try interaction.visualSnapshot(app:app)
        guard snapshot.bounds==frame.windowBounds else { throw fail("Focused window changed during observation") }
        let reusable: PreparedFrame?
        if let cached,VisualTargetPolicy.fresh(capturedAt:cached.frame.capturedAt,now:ProcessInfo.processInfo.systemUptime,originalDigest:cached.frame.digest,currentDigest:frame.digest,originalWindow:cached.frame.windowID,currentWindow:frame.windowID,originalBounds:cached.frame.bounds,currentBounds:frame.bounds) {
            reusable=cached
        } else { reusable=nil }
        var candidates=snapshot.candidates
        if unnamed(candidates) {
            let text: [VisualTextEvidence.Region]
            if let reusable { text=reusable.text }
            else { text=try await ScreenObserver.textEvidence(frame.image) }
            guard stillValid(),epoch==token else { throw fail("Cancelled during visual text recognition") }
            candidates=VisualTextEvidence.augment(candidates,regions:text,frame:frame.bounds)
        }
        let eligible=VisualTargetPolicy.eligible(candidates,target:target,frame:frame.bounds)
        guard eligible.count==1 else { throw fail(eligible.isEmpty ? "No accessible or visible label identifies the requested control" : "Several controls still match; include a position such as top or right") }
        let prepared: ScreenObserver.Frame
        if let cached,sameSurface(cached.frame,frame),
           ScreenObserver.unchangedRegion(eligible[0].bounds,frame:frame.bounds,before:cached.frame.image,after:frame.image) {
            // Current labels determine the only eligible control. Old features
            // may be reused when that region is identical, even if a distant
            // video changed; the prediction must still land on today's target.
            prepared=cached.frame
        } else {
            _ = try await worker.prepare(frameID:frame.id.uuidString,image:frame.image)
            prepared=frame
        }
        guard stillValid(),epoch==token else { throw fail("Cancelled before visual selection") }
        let prediction=try await worker.predict(frameID:prepared.id.uuidString,target:target)
        guard stillValid(),epoch==token,let point=prediction.point,
              let selected=VisualTargetPolicy.select(point:point,candidates:candidates,target:target,frame:frame.bounds) else { throw fail("Visual prediction did not agree with the observed control") }
        guard let fresh=try await observer.capture(app:app),stillValid(),epoch==token,sameSurface(frame,fresh) else { throw fail("Window changed during visual selection; no click sent") }
        var dispatchSnapshot=snapshot,dispatchID=selected.id
        if frame.digest != fresh.digest {
            // Unrelated animation need not veto a stable control. Re-establish
            // every semantic and identity check on the new scene first.
            guard ScreenObserver.unchangedRegion(selected.bounds,frame:frame.bounds,before:frame.image,after:fresh.image) else { throw fail("Target pixels changed during visual selection; no click sent") }
            let current=try interaction.visualSnapshot(app:app)
            guard current.bounds==fresh.windowBounds else { throw fail("Window changed during re-observation") }
            var currentCandidates=current.candidates
            if unnamed(currentCandidates) {
                let text=try await ScreenObserver.textEvidence(fresh.image)
                currentCandidates=VisualTextEvidence.augment(currentCandidates,regions:text,frame:fresh.bounds)
            }
            guard stillValid(),epoch==token,
                  let confirmed=VisualTargetPolicy.select(point:point,candidates:currentCandidates,target:target,frame:fresh.bounds),
                  interaction.sameVisualControl(selected.id,original:snapshot,currentID:confirmed.id,current:current) else { throw fail("Visual target identity or meaning changed; no click sent") }
            // OCR/AX refresh takes time. Sample the target again immediately
            // before input, including the surrounding occlusion margin.
            guard let final=try await observer.capture(app:app),stillValid(),epoch==token,sameSurface(frame,final),
                  ScreenObserver.unchangedRegion(selected.bounds,frame:frame.bounds,before:frame.image,after:final.image) else { throw fail("Target changed during re-observation; no click sent") }
            // Preserve all OCR ownership evidence through the final frame.
            // An unnamed neighbor changing its visible label can introduce a
            // duplicate target even when the chosen button stayed unchanged.
            let unnamedControls=current.candidates.filter {$0.enabled && $0.labels.allSatisfy {$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}}
            guard unnamedControls.allSatisfy({ScreenObserver.unchangedRegion($0.bounds,frame:fresh.bounds,before:fresh.image,after:final.image)}),
                  interaction.sameVisualScene(current,try interaction.visualSnapshot(app:app)),stillValid(),epoch==token else { throw fail("Controls changed during re-observation; no click sent") }
            dispatchSnapshot=current;dispatchID=confirmed.id
        }
        let location=CGPoint(x:frame.bounds.minX+point[0]*frame.bounds.width,y:frame.bounds.minY+point[1]*frame.bounds.height)
        let result=try await interaction.pressVisual(dispatchID,point:location,snapshot:dispatchSnapshot,stillValid:stillValid)
        invalidate()
        return "\(result) · vision \(Int(prediction.predictMs ?? 0)) ms"
    }
}
