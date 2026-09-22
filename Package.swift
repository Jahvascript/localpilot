// swift-tools-version: 5.8
import PackageDescription
let package = Package(name: "LocalPilot", platforms: [.macOS(.v13)], products: [.executable(name: "LocalPilot", targets: ["LocalPilot"])], targets: [.target(name: "PilotCore"), .executableTarget(name: "LocalPilot", dependencies: ["PilotCore"]), .testTarget(name: "PilotCoreTests", dependencies: ["PilotCore"])])
