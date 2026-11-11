// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Junction", platforms: [.macOS(.v13)], products: [.library(name: "JunctionCore", targets: ["JunctionCore"]), .executable(name: "URLLinker", targets: ["JunctionApp"])], targets: [
.target(name: "JunctionCore", resources: [.copy("Resources/rewriters.json"), .copy("Resources/tracking-params.json"), .copy("Resources/starter-rules.json"), .copy("Resources/MenuBarIcon.svg")]),
.target(name: "JunctionMacKit", dependencies: ["JunctionCore"]),
.executableTarget(name: "JunctionApp", dependencies: ["JunctionCore", "JunctionMacKit"], path: "Sources/URLLinker"),
.testTarget(name: "JunctionCoreTests", dependencies: ["JunctionCore"]),
.testTarget(name: "JunctionMacKitTests", dependencies: ["JunctionMacKit", "JunctionCore"])
])
