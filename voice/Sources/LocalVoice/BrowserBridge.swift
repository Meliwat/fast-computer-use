import Foundation
import Darwin
import VoiceCore

final class BrowserBridge: @unchecked Sendable {
    private let work = DispatchQueue(label:"localvoice.browser",qos:.userInitiated)
    private func failure(_ message: String) -> NSError { NSError(domain:"LocalVoiceBrowser",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    func requireVerifiedDispatch(existingText:Bool=false,sequence:Bool=false) async throws {
        let data=try await exchange(BrowserCommand(op:"capabilities"))
        let capabilities=try JSONDecoder().decode(BrowserCapabilities.self,from:data)
        if existingText {try capabilities.requireExistingText()}
        else {try capabilities.requireVerifiedDispatch()}
        if sequence {try capabilities.requireSequenceDispatch()}
    }
    func observe(target: String? = nil) async throws -> BrowserObservation {
        let data = try await exchange(BrowserCommand(op:"observe",target:target))
        let reply = try JSONDecoder().decode(BrowserObservationReply.self,from:data)
        guard reply.ok, let observation = reply.observation else { throw failure(reply.error ?? "Page observation unavailable") }
        return observation
    }
    func performResult(_ command: BrowserCommand) async throws -> BrowserActionResult {
        let data = try await exchange(command)
        let reply = try JSONDecoder().decode(BrowserActionResult.self,from:data)
        guard reply.ok else { throw failure(reply.error ?? "Browser action failed") }
        return reply
    }
    func perform(_ command: BrowserCommand) async throws -> String {
        let started = ProcessInfo.processInfo.systemUptime
        let data = try await exchange(command)
        let reply = try JSONDecoder().decode(BrowserActionResult.self,from:data)
        guard reply.ok else { throw failure(reply.error ?? "Browser action failed") }
        let ms = Int((ProcessInfo.processInfo.systemUptime-started)*1000)
        return "\(reply.summary) · \(ms) ms"
    }
    private func exchange(_ command: BrowserCommand) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            work.async {
                do {
                    let fd = socket(AF_UNIX,SOCK_STREAM,0)
                    guard fd >= 0 else { throw self.failure("Could not connect to Chrome") }
                    defer { close(fd) }
                    var noSigPipe: Int32 = 1
                    setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSigPipe,socklen_t(MemoryLayout<Int32>.size))
                    var timeout = timeval(tv_sec:3,tv_usec:0)
                    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
                    let path = NSHomeDirectory()+"/Library/Application Support/LocalVoice/browser.sock"
                    var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
                    guard path.utf8.count < MemoryLayout.size(ofValue:address.sun_path) else { throw self.failure("Browser connection path is too long") }
                    _ = withUnsafeMutablePointer(to:&address.sun_path) { pointer in
                        pointer.withMemoryRebound(to:CChar.self,capacity:104) { destination in path.withCString { source in strcpy(destination, source) } }
                    }
                    let connected = withUnsafePointer(to:&address) { pointer in
                        pointer.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) }
                    }
                    guard connected == 0 else { throw self.failure("Chrome voice connection unavailable; check that Local Voice Browser is enabled") }
                    var body = try JSONSerialization.jsonObject(with:JSONEncoder().encode(command)) as! [String:Any]
                    body["commandId"] = UUID().uuidString
                    body["deadline"] = Date().addingTimeInterval(2).timeIntervalSince1970 * 1000
                    var bytes = try JSONSerialization.data(withJSONObject:body); bytes.append(10)
                    try bytes.withUnsafeBytes { raw in
                        var sent = 0
                        while sent < raw.count {
                            let n = Darwin.write(fd,raw.baseAddress!.advanced(by:sent),raw.count-sent)
                            guard n > 0 else { throw self.failure("Browser connection closed before request completed") }
                            sent += n
                        }
                    }
                    var response = Data(), buffer = [UInt8](repeating:0,count:4096)
                    while !response.contains(10) && response.count <= 65536 {
                        let count = Darwin.read(fd,&buffer,buffer.count)
                        guard count > 0 else { throw self.failure("Browser did not acknowledge; not retrying") }
                        response.append(contentsOf:buffer.prefix(count))
                    }
                    guard response.count <= 65536 else { throw self.failure("Browser response exceeded the bounded message size") }
                    continuation.resume(returning:response)
                } catch { continuation.resume(throwing:error) }
            }
        }
    }
}
