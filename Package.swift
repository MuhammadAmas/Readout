// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Readout",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Readout", targets: ["Readout"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.15.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ReadoutCore",
            path: "Readout",
            exclude: ["App", "Hotkeys", "Selection", "Speech/Engines", "Speech/CSherpaOnnx", "UI"],
            sources: ["TextCleanup", "Speech/Core"]
        ),
        .target(
            name: "CSherpaOnnx",
            path: "Readout/Speech/CSherpaOnnx"
        ),
        .executableTarget(
            name: "Readout",
            dependencies: [
                "ReadoutCore",
                "CSherpaOnnx",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "Readout",
            exclude: ["TextCleanup", "Speech/Core", "Speech/CSherpaOnnx"],
            sources: ["App", "Hotkeys", "Selection", "Speech/Engines", "UI"]
        ),
        .testTarget(
            name: "ReadoutCoreTests",
            dependencies: ["ReadoutCore"],
            path: "Tests/ReadoutCoreTests"
        ),
    ]
)
