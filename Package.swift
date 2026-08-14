// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CodexMeterCore", targets: ["CodexMeterCore"]),
        .executable(name: "CodexMeter", targets: ["CodexMeter"]),
        .executable(name: "CodexMeterTests", targets: ["CodexMeterTests"])
    ],
    targets: [
        .target(
            name: "CodexMeterCore",
            path: "Sources/CodexMeterCore"
        ),
        .executableTarget(
            name: "CodexMeter",
            dependencies: ["CodexMeterCore"],
            path: "Sources/CodexMeter",
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "CodexMeterTests",
            dependencies: ["CodexMeterCore"],
            path: "Tests/CodexMeterTestRunner"
        )
    ],
    swiftLanguageModes: [.v5]
)
