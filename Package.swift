// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClearMic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClearMic", targets: ["ClearMic"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "ClearMicAudio", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("CoreAudio")]),
        .executableTarget(name: "ClearMic", dependencies: ["ClearMicAudio", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.linkedFramework("AVFoundation"), .linkedFramework("SwiftUI"),
                                           .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "ClearMicAudioTests", dependencies: ["ClearMicAudio"])
    ],
    cxxLanguageStandard: .cxx17
)
