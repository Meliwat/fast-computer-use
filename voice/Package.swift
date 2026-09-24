// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LocalVoice", platforms: [.macOS(.v14)], products: [.executable(name: "LocalVoice", targets: ["LocalVoice"])], targets: [.target(name: "VoiceCore"), .target(name: "VoicePerception", dependencies: ["VoiceCore"]), .executableTarget(name: "LocalVoice", dependencies: ["VoiceCore", "VoicePerception"]), .testTarget(name: "VoiceCoreTests", dependencies: ["VoiceCore"]), .testTarget(name: "VoicePerceptionTests", dependencies: ["VoicePerception"])], swiftLanguageModes: [.v5])
