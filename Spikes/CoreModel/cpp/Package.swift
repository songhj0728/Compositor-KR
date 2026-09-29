// swift-tools-version: 5.9
// Spike: can Swift (the macOS app's language) use the C++ Core directly, through Swift's C++ interoperability?
// Not part of the app. See ../README.md.
import PackageDescription

let package = Package(
    name: "CoreModelCppSpike",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CoreModelCpp", path: ".", sources: ["src/core.cpp"], publicHeadersPath: "include"),
        .testTarget(name: "SwiftUsesCppTests", dependencies: ["CoreModelCpp"], path: "swift-interop",
                    swiftSettings: [.interoperabilityMode(.Cxx)]),
    ],
    cxxLanguageStandard: .cxx20
)
