// swift-tools-version: 5.9
// Spike: a platform-independent document model in Swift, built with SwiftPM on Windows and macOS (and openable in
// Xcode). Not part of the app. See ../README.md.
import PackageDescription

let package = Package(
    name: "CoreModelSpike",
    platforms: [.macOS(.v13)],
    products: [
        // The Core itself, for Swift callers (the macOS app, a Swift Windows app).
        .library(name: "CoreModel", targets: ["CoreModel"]),
        // The Core behind a C ABI (../include/compositor_core.h), for C++, C# or WinUI callers.
        .library(name: "CompositorCore", type: .dynamic, targets: ["CoreModelCABI"]),
        .executable(name: "WindowsAPIDemo", targets: ["WindowsAPIDemo"]),
    ],
    targets: [
        // Swift standard library only: no Foundation, no platform frameworks.
        .target(name: "CoreModel"),
        .target(name: "CoreModelCABI", dependencies: ["CoreModel"]),
        .executableTarget(
            name: "WindowsAPIDemo",
            dependencies: ["CoreModel"],
            linkerSettings: [
                .linkedLibrary("User32", .when(platforms: [.windows])),
                .linkedLibrary("Shell32", .when(platforms: [.windows])),
                .linkedLibrary("Ole32", .when(platforms: [.windows])),
            ]
        ),
        .testTarget(name: "CoreModelTests", dependencies: ["CoreModel"]),
    ]
)
