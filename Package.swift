// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FocusCore", platforms: [.macOS(.v14)], products: [.library(name: "FocusCore", targets: ["FocusCore"])], targets: [.target(name: "FocusCore", path: "Core"), .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"], path: "Tests")])
