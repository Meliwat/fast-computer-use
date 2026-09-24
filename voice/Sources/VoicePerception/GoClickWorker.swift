import Foundation
import Darwin
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import VoiceCore

/// One resident model, serialized away from the UI. Private pipes, no network listener.
public final class GoClickWorker: @unchecked Sendable {
    public struct Reply: Decodable {
        public let id: String
        public let ok: Bool
        public let error: String?
        public let frameId: String?
        public let point: [Double]?
        public let prepareMs: Double?
        public let predictMs: Double?
    }
    private let queue=DispatchQueue(label:"localvoice.vision",qos:.userInitiated)
    private var process: Process?
    private var inputPipe: Pipe?, outputPipe: Pipe?
    private let configuration: [String:String]?
    public init(configuration: [String:String]? = nil) { self.configuration=configuration }
    private func fail(_ text: String) -> NSError { NSError(domain:"LocalVoiceVision",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    private func start() throws {
        if process?.isRunning == true { return }
        let config: [String:String]
        if let configuration { config=configuration }
        else {
            guard let url=Bundle.main.url(forResource:"VisionConfig",withExtension:"json") else { throw fail("Local vision is not installed; rebuild with GoClick configured") }
            guard let resources=Bundle.main.resourceURL else { throw fail("App resources are missing") }
            config=try RuntimeConfiguration.resolve(JSONDecoder().decode([String:String].self,from:Data(contentsOf:url)),resources:resources)
        }
        guard let python=config["python"],let worker=config["worker"],let model=config["model"],
              FileManager.default.isExecutableFile(atPath:python),FileManager.default.fileExists(atPath:worker),FileManager.default.fileExists(atPath:model) else { throw fail("Local GoClick runtime or weights are missing") }
        let child=Process(), input=Pipe(), output=Pipe()
        child.executableURL=URL(fileURLWithPath:python);child.arguments=[worker,model]
        var env=ProcessInfo.processInfo.environment
        env["HF_HUB_DISABLE_TELEMETRY"]="1";env["HF_HUB_OFFLINE"]="1";env["TRANSFORMERS_OFFLINE"]="1";env["OMP_NUM_THREADS"]="4";env["PYTHONUNBUFFERED"]="1"
        env["PYTHONDONTWRITEBYTECODE"]="1";child.environment=env;child.standardInput=input;child.standardOutput=output;child.standardError=FileHandle.nullDevice
        try child.run()
        process=child;inputPipe=input;outputPipe=output
        // Convert a closed pipe to an error, never terminate the voice app with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor,F_SETNOSIGPIPE,1)
    }
    private func stopWorker() {
        try? inputPipe?.fileHandleForWriting.close()
        try? outputPipe?.fileHandleForReading.close()
        if process?.isRunning == true { process?.terminate() }
        process=nil;inputPipe=nil;outputPipe=nil
    }
    public func shutdown() { queue.async { self.stopWorker() } }
    public func warm() async throws { _ = try await exchange(["op":"warm"]) }
    public func clear() async {
        // Do not spawn a model just to clear a cache.
        await withCheckedContinuation { continuation in
            queue.async {
                if self.process?.isRunning == true {
                    do { _ = try self.exchangeSync(["op":"clear"]) } catch { self.stopWorker() }
                }
                continuation.resume()
            }
        }
    }
    public func prepare(frameID: String, image: CGImage) async throws -> Reply {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let imageData=try Self.encode(image)
                    let digest=SHA256.hash(data:imageData).map { String(format:"%02x",$0) }.joined()
                    continuation.resume(returning:try self.exchangeSync(["op":"prepare","frameId":frameID,"image":imageData.base64EncodedString(),"imageSHA256":digest]))
                } catch { self.stopWorker();continuation.resume(throwing:error) }
            }
        }
    }
    public func predict(frameID: String, target: String) async throws -> Reply {
        try await exchange(["op":"predict","frameId":frameID,"target":target])
    }
    private func exchange(_ request: [String:Any]) async throws -> Reply {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning:try self.exchangeSync(request)) }
                catch { self.stopWorker();continuation.resume(throwing:error) }
            }
        }
    }
    private func exchangeSync(_ request: [String:Any]) throws -> Reply {
        let launching=process?.isRunning != true
        try start()
        let id=UUID().uuidString
        var request=request;request["id"]=id
        var bytes=try JSONSerialization.data(withJSONObject:request);bytes.append(10)
        guard bytes.count <= 8*1024*1024,let input=inputPipe?.fileHandleForWriting,let output=outputPipe?.fileHandleForReading else { throw fail("Vision request unavailable or too large") }
        // Nonblocking writes have a deadline too (a hung worker cannot strand the queue).
        let fd=input.fileDescriptor,flags=fcntl(fd,F_GETFL)
        _ = fcntl(fd,F_SETFL,flags | O_NONBLOCK)
        defer { _ = fcntl(fd,F_SETFL,flags) }
        // A fresh dependency environment can spend >15 s importing libraries
        // and compiling its first MLX graph. Warm startup remains off the UI
        // actor; subsequent frame/target requests keep the shorter deadline.
        let deadline=ProcessInfo.processInfo.systemUptime+(launching ? 45 : 15)
        try bytes.withUnsafeBytes { raw in
            var offset=0
            while offset<raw.count {
                guard ProcessInfo.processInfo.systemUptime<deadline else { throw fail("Local vision timed out") }
                var descriptor=pollfd(fd:fd,events:Int16(POLLOUT),revents:0)
                if poll(&descriptor,1,50)<=0 { continue }
                let written=Darwin.write(fd,raw.baseAddress!.advanced(by:offset),raw.count-offset)
                if written<0 && (errno==EAGAIN || errno==EINTR) { continue }
                guard written>0 else { throw fail("Local vision worker closed") }
                offset+=written
            }
        }
        var data=Data(), buffer=[UInt8](repeating:0,count:4096)
        while ProcessInfo.processInfo.systemUptime<deadline && data.count<16384 {
            var descriptor=pollfd(fd:output.fileDescriptor,events:Int16(POLLIN),revents:0)
            if poll(&descriptor,1,50)<=0 { continue }
            let count=Darwin.read(output.fileDescriptor,&buffer,buffer.count)
            guard count>0 else { throw fail("Local vision worker closed") }
            data.append(contentsOf:buffer.prefix(count))
            if data.contains(10) {
                let reply=try JSONDecoder().decode(Reply.self,from:data)
                guard reply.id==id else { throw fail("Vision reply identity mismatch") }
                guard reply.ok else { throw fail(reply.error ?? "Vision could not select a target") }
                if let expected=request["frameId"] as? String, reply.frameId != expected { throw fail("Vision frame identity mismatch") }
                return reply
            }
        }
        throw fail("Local vision timed out; no action dispatched")
    }
    static func encode(_ image: CGImage) throws -> Data {
        let scale=min(1,1024/Double(max(image.width,image.height)))
        let width=max(1,Int(Double(image.width)*scale)),height=max(1,Int(Double(image.height)*scale))
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NSError(domain:"VisionImage",code:1) }
        context.interpolationQuality = .high
        context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        let data=NSMutableData()
        guard let scaled=context.makeImage(),let destination=CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else { throw NSError(domain:"VisionImage",code:2) }
        CGImageDestinationAddImage(destination,scaled,nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain:"VisionImage",code:3) }
        return data as Data
    }
}
