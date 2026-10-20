// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FokusBar", platforms: [.macOS(.v14)], products: [.executable(name: "FokusBar", targets: ["FokusBar"])], targets: [.target(name: "FocusCore"), .executableTarget(name: "FokusBar", dependencies: ["FocusCore"]), .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"])], swiftLanguageModes: [.v5])
