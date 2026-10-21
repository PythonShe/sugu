// swift-tools-version: 6.1

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

/// AzooKey with the Zenzai trait is built with C++ interop, and Swift requires
/// every module that imports a C++-interop module to enable it as well.
let cxxSwiftSettings = swiftSettings + [.interoperabilityMode(.Cxx)]

let package = Package(
    name: "SuguKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SuguInput", targets: ["SuguInput"]),
        .library(name: "SuguEngines", targets: ["SuguEngines"]),
        .library(name: "SuguCore", targets: ["SuguCore"]),
        .library(name: "SuguLearning", targets: ["SuguLearning"]),
        .library(name: "SuguDictionaries", targets: ["SuguDictionaries"]),
        .library(name: "SuguDownloads", targets: ["SuguDownloads"]),
        .library(name: "SuguUpdates", targets: ["SuguUpdates"]),
        .executable(name: "sugu-tool", targets: ["sugu-tool"]),
        .executable(name: "sugu-bench", targets: ["sugu-bench"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
            exact: "0.11.2",
            traits: ["Zenzai"]
        ),
        // Keep in step with SPARKLE_VERSION in scripts/versions.sh.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .binaryTarget(name: "librime", path: "../../Frameworks/librime.xcframework"),
        .target(
            name: "CRimeShim",
            dependencies: ["librime"],
            linkerSettings: [.linkedLibrary("c++")]
        ),
        .target(name: "SuguCore", swiftSettings: swiftSettings),
        .target(
            name: "SuguRime",
            dependencies: ["SuguCore", "SuguLM", "CRimeShim", "librime"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SuguAzooKey",
            dependencies: [
                "SuguCore",
                "SuguLM",
                .product(
                    name: "KanaKanjiConverterModuleWithDefaultDictionary",
                    package: "AzooKeyKanaKanjiConverter"
                ),
            ],
            swiftSettings: cxxSwiftSettings
        ),
        .target(
            name: "SuguLearning",
            dependencies: ["SuguCore", "SuguLM"],
            swiftSettings: swiftSettings,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "SuguDictionaries",
            dependencies: ["SuguCore", "SuguLearning"],
            swiftSettings: swiftSettings
        ),
        .target(name: "SuguDownloads", swiftSettings: swiftSettings),
        .target(name: "SuguLM", swiftSettings: swiftSettings),
        .target(
            name: "SuguUpdates",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SuguInput",
            dependencies: ["SuguCore", "SuguLearning"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SuguEngines",
            dependencies: ["SuguInput", "SuguCore", "SuguRime", "SuguAzooKey", "SuguLearning", "SuguDownloads", "SuguLM"],
            swiftSettings: cxxSwiftSettings
        ),
        .executableTarget(
            name: "sugu-tool",
            dependencies: ["SuguRime", "SuguAzooKey", "SuguCore", "SuguLM"],
            swiftSettings: cxxSwiftSettings
        ),
        .executableTarget(
            name: "sugu-bench",
            dependencies: ["SuguEngines", "SuguInput", "SuguCore", "SuguLearning", "SuguRime"],
            swiftSettings: cxxSwiftSettings
        ),
        .testTarget(name: "SuguCoreTests", dependencies: ["SuguCore"], swiftSettings: swiftSettings),
        .testTarget(
            name: "SuguInputTests",
            dependencies: ["SuguInput", "SuguCore", "SuguLearning", "SuguLM"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SuguLearningTests",
            dependencies: ["SuguLearning", "SuguCore", "SuguLM"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SuguDictionariesTests",
            dependencies: ["SuguDictionaries", "SuguLearning", "SuguCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(name: "SuguDownloadsTests", dependencies: ["SuguDownloads"], swiftSettings: swiftSettings),
        .testTarget(name: "SuguLMTests", dependencies: ["SuguLM"], swiftSettings: swiftSettings),
        .testTarget(
            name: "SuguEngineTests",
            dependencies: ["SuguEngines", "SuguDownloads", "SuguRime", "SuguAzooKey", "SuguCore", "SuguLM"],
            swiftSettings: cxxSwiftSettings
        ),
    ]
)
