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
        .library(name: "SuguCore", targets: ["SuguCore"]),
        .library(name: "SuguLearning", targets: ["SuguLearning"]),
        .library(name: "SuguDictionaries", targets: ["SuguDictionaries"]),
        .executable(name: "sugu-tool", targets: ["sugu-tool"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
            exact: "0.11.2",
            traits: ["Zenzai"]
        ),
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
            dependencies: ["SuguCore", "CRimeShim", "librime"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SuguAzooKey",
            dependencies: [
                "SuguCore",
                .product(
                    name: "KanaKanjiConverterModuleWithDefaultDictionary",
                    package: "AzooKeyKanaKanjiConverter"
                ),
            ],
            swiftSettings: cxxSwiftSettings
        ),
        .target(
            name: "SuguLearning",
            dependencies: ["SuguCore"],
            swiftSettings: swiftSettings,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "SuguDictionaries",
            dependencies: ["SuguCore", "SuguLearning"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SuguInput",
            dependencies: ["SuguCore", "SuguRime", "SuguAzooKey", "SuguLearning"],
            swiftSettings: cxxSwiftSettings
        ),
        .executableTarget(
            name: "sugu-tool",
            dependencies: ["SuguInput", "SuguRime", "SuguAzooKey", "SuguCore"],
            swiftSettings: cxxSwiftSettings
        ),
        .testTarget(name: "SuguCoreTests", dependencies: ["SuguCore"], swiftSettings: swiftSettings),
        .testTarget(
            name: "SuguInputTests",
            dependencies: ["SuguInput", "SuguCore", "SuguLearning"],
            swiftSettings: cxxSwiftSettings
        ),
        .testTarget(
            name: "SuguLearningTests",
            dependencies: ["SuguLearning", "SuguCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SuguDictionariesTests",
            dependencies: ["SuguDictionaries", "SuguLearning", "SuguCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SuguEngineTests",
            dependencies: ["SuguRime", "SuguAzooKey", "SuguCore"],
            swiftSettings: cxxSwiftSettings
        ),
    ]
)
