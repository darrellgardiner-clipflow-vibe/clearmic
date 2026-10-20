// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClearMic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClearMic", targets: ["ClearMic"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "RNNoise", path: "vendor/RNNoise", sources: [
            "src/denoise.c", "src/rnn.c", "src/pitch.c", "src/kiss_fft.c", "src/celt_lpc.c",
            "src/nnet.c", "src/nnet_default.c", "src/parse_lpcnet_weights.c", "src/rnnoise_data.c", "src/rnnoise_tables.c"
        ], publicHeadersPath: "include", cSettings: [.headerSearchPath("src"), .headerSearchPath("compat")]),
        .target(name: "ClearMicAudio", dependencies: ["RNNoise"], publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("CoreAudio")]),
        .executableTarget(name: "ClearMic", dependencies: ["ClearMicAudio", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.linkedFramework("AVFoundation"), .linkedFramework("SwiftUI"),
                                           .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "ClearMicAudioTests", dependencies: ["ClearMicAudio", "ClearMic"], resources: [.copy("Fixtures")])
    ],
    cxxLanguageStandard: .cxx17
)
