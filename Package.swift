// swift-tools-version: 6.0
import PackageDescription

let homebrew = "/opt/homebrew"
let vendor = Context.packageDirectory + "/Vendor"
// TagLib: Homebrew's by default. Releases set PREGAME_TAGLIB_PREFIX to the one
// scripts/build-taglib.sh builds from source for the minimum macOS (docs/releasing.md).
let taglib = Context.environment["PREGAME_TAGLIB_PREFIX"].map {
    $0.hasPrefix("/") ? $0 : Context.packageDirectory + "/" + $0
} ?? homebrew

let package = Package(
    name: "Pregame",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Pregame", targets: ["PregameApp"]),
    ],
    dependencies: [
        // Sparkle (MIT): in-app updates from an EdDSA-signed appcast. Pinned to
        // an exact version; scripts/build-app.sh embeds and signs the framework.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
        // Sentry (MIT): crash reports, only with the Mix Host's consent
        // (docs/privacy.md). The build without the UIKit/AppKit integrations, so
        // it can't collect window titles or UI breadcrumbs; scripts/build-app.sh
        // embeds and signs the framework.
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.33.0"),
    ],
    targets: [
        // Queen Mary DSP (GPL-2.0+), vendored from Mixxx 2.5, plus a C shim.
        .target(
            name: "QMDSP",
            path: "Sources/QMDSP",
            exclude: ["COPYING", "ext/kissfft/CHANGELOG", "ext/kissfft/COPYING",
                      "ext/kissfft/README"],
            publicHeadersPath: "shim",
            cSettings: [
                .define("kiss_fft_scalar", to: "double"),
                .headerSearchPath("."),
            ],
            cxxSettings: [
                .define("kiss_fft_scalar", to: "double"),
                .headerSearchPath("."),
                .unsafeFlags(["-w"]),  // third-party code: silence warnings
            ]
        ),
        // TagLib (LGPL); bundled into the .app by scripts/build-app.sh.
        .target(
            name: "CTagLib",
            path: "Sources/CTagLib",
            publicHeadersPath: "include",
            cxxSettings: [.unsafeFlags(["-I\(taglib)/include"])],
            linkerSettings: [
                .unsafeFlags(["-L\(taglib)/lib"]),
                .linkedLibrary("tag"),
            ]
        ),
        // Rubber Band (GPL-2.0+) + libsamplerate, linked statically from Homebrew.
        .target(
            name: "CRubberBand",
            path: "Sources/CRubberBand",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-I\(homebrew)/include"])],
            linkerSettings: [
                .unsafeFlags(["\(homebrew)/lib/librubberband.a", "\(homebrew)/lib/libsamplerate.a"]),
                .linkedFramework("Accelerate"),
                .linkedLibrary("c++"),
            ]
        ),
        // LAME (LGPL) MP3 encoder, linked statically from Homebrew.
        .target(
            name: "CLame",
            path: "Sources/CLame",
            publicHeadersPath: "include",
            linkerSettings: [.unsafeFlags(["\(homebrew)/lib/libmp3lame.a", "\(homebrew)/lib/libmpg123.a"])]
        ),
        // ONNX Runtime (MIT), prebuilt in Vendor/onnxruntime, for Demucs stems;
        // bundled into the .app by scripts/build-app.sh.
        .target(
            name: "COnnx",
            path: "Sources/COnnx",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-I\(vendor)/onnxruntime/include"])],
            linkerSettings: [
                .unsafeFlags(["\(vendor)/onnxruntime/lib/libonnxruntime.1.dylib",
                              "-Xlinker", "-rpath", "-Xlinker", "\(vendor)/onnxruntime/lib"]),
            ]
        ),
        .target(
            name: "PregameCore",
            dependencies: ["QMDSP", "CTagLib", "CRubberBand", "CLame", "COnnx"],
            resources: [.process("Resources")],
            // Optimised in debug builds too: the engine's per-sample loops (analysis,
            // rendering) run 5–10× slower at -Onone, which made a plain `swift test`
            // take about 6 minutes instead of 1. Remove this line locally if you
            // need to step through the core in a debugger.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .executableTarget(
            name: "PregameApp",
            dependencies: ["PregameCore", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "Sentry-WithoutUIKitOrAppKit", package: "sentry-cocoa")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PregameCoreTests",
            dependencies: ["PregameCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "PregameAppTests",
            dependencies: ["PregameApp", "PregameCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
