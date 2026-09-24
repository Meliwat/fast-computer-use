import Foundation
import Darwin
import VoiceCore

struct LearnedResult: Decodable {
    let action: String
    let value: String
    let confidence: Double
    let milliseconds: Double
}
/// One resident worker, serialized off the main actor. Execution stays in the native action router.
final class LearnedParser: @unchecked Sendable {
    private let work = DispatchQueue(label: "localvoice.parser", qos: .userInitiated)
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var input: FileHandle?
    private var output: FileHandle?
    private func failure(_ text: String) -> NSError { NSError(domain: "LocalParser", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func start() throws {
        if process?.isRunning == true { return }
        guard let url=Bundle.main.url(forResource:"ParserConfig",withExtension:"json"),let resources=Bundle.main.resourceURL else { throw failure("Rebuild the app to configure the local parser") }
        let config=try RuntimeConfiguration.resolve(JSONDecoder().decode([String:String].self,from:Data(contentsOf:url)),resources:resources)
        guard let python=config["python"],let script=config["worker"] else { throw failure("Incomplete parser runtime configuration") }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = URL(fileURLWithPath: python); child.arguments = [script]
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"; env["TRANSFORMERS_OFFLINE"] = "1"
        if let models=config["models"] { env["LOCALVOICE_MODEL_DIR"]=models }
        env["PYTHONDONTWRITEBYTECODE"]="1"
        child.environment = env
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
        try child.run()
        process = child; inputPipe = stdin; outputPipe = stdout; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
    }
    private func readLine() throws -> Data {
        guard let output else { throw failure("Parser not started") }
        let deadline = Date().addingTimeInterval(12)
        var data = Data()
        while Date() < deadline && data.count < 16384 {
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            if poll(&descriptor, 1, 100) > 0 {
                var byte: UInt8 = 0
                guard Darwin.read(output.fileDescriptor, &byte, 1) == 1 else { throw failure("Parser worker closed") }
                if byte == 10 { return data }; data.append(byte)
            }
        }
        throw failure("Local parser timed out")
    }
    func predict(_ text: String) async throws -> LearnedResult {
        try await withCheckedThrowingContinuation { continuation in
            work.async {
                do {
                    try self.start()
                    var data = try JSONSerialization.data(withJSONObject: ["text":text]); data.append(10)
                    guard let input = self.input else { throw self.failure("Parser input unavailable") }
                    try input.write(contentsOf: data)
                    let result = try JSONDecoder().decode(LearnedResult.self, from: self.readLine())
                    continuation.resume(returning: result)
                } catch {
                    self.process?.terminate(); self.process = nil
                    self.input = nil; self.output = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    func shutdown() { work.async { self.process?.terminate(); self.process=nil; try? self.input?.close(); try? self.output?.close(); self.input=nil; self.output=nil; self.inputPipe=nil; self.outputPipe=nil } }
    deinit { process?.terminate() }
}
