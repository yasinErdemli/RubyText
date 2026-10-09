// swift-tools-version: 6.2

import PackageDescription

// Approachable concurrency, as in the demo app, in the Swift 5 language
// mode. RubyUI also isolates to the main actor by default; RubyCore and
// RubyTransliteration are plain data and stay nonisolated.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "RubyText",
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0")],
    products: [
        /// Kana to romaji, hiragana to katakana and back, with no
        /// dictionary and only the standard library.
        .library(name: "RubyTransliteration", targets: ["RubyTransliteration"]),
    ],
    dependencies: [
        .package(url: "https://github.com/shinjukunian/Mecab-Swift", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "RubyTransliteration",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RubyTransliterationTests",
            dependencies: ["RubyTransliteration"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v5]
)

// RubyCore reads with Mecab-Swift, whose tokenizer uses CoreFoundation's,
// and RubyUI draws with SwiftUI, so they're on Apple platforms only.
// RubyTransliteration builds anywhere Swift does, Linux included.
#if canImport(Darwin)
package.products += [
    /// Readings as plain data: analysis, markup, dictionary lookups.
    .library(name: "RubyCore", targets: ["RubyCore"]),
    /// SwiftUI views that draw furigana and romaji.
    .library(name: "RubyUI", targets: ["RubyUI"]),
]
package.targets += [
    .target(
        name: "RubyCore",
        dependencies: [
            "RubyTransliteration",
            .product(name: "Mecab-Swift", package: "Mecab-Swift"),
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "RubyUI",
        dependencies: ["RubyCore", "RubyTransliteration"],
        swiftSettings: swiftSettings + [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(
        name: "RubyCoreTests",
        dependencies: [
            "RubyCore",
            "RubyTransliteration",
            // Apps bundle their own dictionary; tests read with this one.
            .product(name: "IPADic", package: "Mecab-Swift"),
        ],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "RubyUITests",
        dependencies: [
            "RubyCore",
            "RubyTransliteration",
            "RubyUI",
            // Apps bundle their own dictionary; tests read with this one.
            .product(name: "IPADic", package: "Mecab-Swift"),
        ],
        swiftSettings: swiftSettings + [.defaultIsolation(MainActor.self)]
    ),
]
#endif
