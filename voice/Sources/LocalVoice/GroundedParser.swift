import Foundation
import Darwin
import VoiceCore

/// Resident offline worker. Only proposals leave this class; the native router owns execution.
final class GroundedParser: @unchecked Sendable {
    private let work=DispatchQueue(label:"localvoice.grounded",qos:.userInitiated)
    private var process: Process?
    private var pipes: [Pipe]=[]
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffered=Data()
    private func failure(_ message:String)->NSError { NSError(domain:"GroundedParser",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    private func reset() {
        process?.terminate();process=nil
        try? input?.close();try? output?.close();input=nil;output=nil;pipes=[];buffered.removeAll()
    }
    private func start() throws {
        if process?.isRunning==true { return }
        reset()
        guard let url=Bundle.main.url(forResource:"GroundedConfig",withExtension:"json"),let resources=Bundle.main.resourceURL else { throw failure("Rebuild the app to configure experimental grounded commands") }
        let config=try RuntimeConfiguration.resolve(JSONDecoder().decode([String:String].self,from:Data(contentsOf:url)),resources:resources)
        guard let python=config["python"],let script=config["worker"] else { throw failure("Incomplete grounding runtime configuration") }
        let child=Process(),stdin=Pipe(),stdout=Pipe()
        child.executableURL=URL(fileURLWithPath:python);child.arguments=[script,"--grounded-v2"]
        var env=ProcessInfo.processInfo.environment;env["HF_HUB_OFFLINE"]="1";env["TRANSFORMERS_OFFLINE"]="1"
        if let models=config["models"] { env["LOCALVOICE_MODEL_DIR"]=models }
        env["PYTHONDONTWRITEBYTECODE"]="1";child.environment=env;child.standardInput=stdin;child.standardOutput=stdout;child.standardError=FileHandle.nullDevice
        try child.run();process=child;pipes=[stdin,stdout];input=stdin.fileHandleForWriting;output=stdout.fileHandleForReading
    }
    private func readLine() throws -> Data {
        guard let output else { throw failure("Grounding worker not started") }
        let deadline=ProcessInfo.processInfo.systemUptime+12
        while ProcessInfo.processInfo.systemUptime<deadline {
            if let end=buffered.firstIndex(of:10) { let line=Data(buffered[..<end]);buffered.removeSubrange(...end);return line }
            guard buffered.count<65536 else { throw failure("Grounding reply too large") }
            var fd=pollfd(fd:output.fileDescriptor,events:Int16(POLLIN),revents:0)
            if poll(&fd,1,100)>0 {
                var bytes=[UInt8](repeating:0,count:4096)
                let count=Darwin.read(output.fileDescriptor,&bytes,bytes.count)
                guard count>0 else { throw failure("Grounding worker unavailable; check its local model setup") }
                buffered.append(contentsOf:bytes.prefix(count))
            }
        }
        throw failure("Local grounding timed out; no action sent")
    }
    private func exchange<T:Decodable>(_ object:[String:Any], as type:T.Type) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            work.async {
                do {
                    try self.start()
                    var data=try JSONSerialization.data(withJSONObject:object)
                    guard data.count<=65536,let input=self.input else { throw self.failure("Grounding request unavailable or too large") }
                    data.append(10);try input.write(contentsOf:data)
                    let result=try JSONDecoder().decode(type,from:self.readLine())
                    continuation.resume(returning:result)
                } catch { self.reset();continuation.resume(throwing:error) }
            }
        }
    }
    func predict(_ text:String, observation:BrowserObservation, requestID:String) async throws -> GroundedProposal {
        let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(observation))
        return try await exchange(["id":requestID,"text":text,"observation":encoded],as:GroundedProposal.self)
    }
    func preflight(_ texts:[String],requestID:String,requiredOperations:[String?]?=nil) async throws -> Bool {
        let result=try await exchange(["id":requestID,"kind":"preflight","texts":texts],as:GroundedPreflight.self)
        return result.accepts(requestID:requestID,count:texts.count,requiredOperations:requiredOperations)
    }
    func warm() async throws {
        let id=UUID().uuidString
        let result=try await exchange(["id":id,"text":"open Downloads","observation":["version":1,"documentId":"warm","observationId":"warm","truncated":false,"candidates":[]]],as:GroundedProposal.self)
        guard result.id==id, result.error==nil else { throw failure("Grounding worker failed to warm") }
    }
    func shutdown() { work.async { self.reset() } }
    deinit { process?.terminate() }
}
