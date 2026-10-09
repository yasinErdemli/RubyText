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
        /// Readings as plain data: analysis, markup, dictionary lookups.
        .library(name: "RubyCore", targets: ["RubyCore"]),
        /// SwiftUI views that draw furigana and romaji.
        .library(name: "RubyUI", targets: ["RubyUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/shinjukunian/Mecab-Swift", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "RubyTransliteration",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RubyCore",
            dependencies: [
                "RubyTransliteration",
                .product(name: "Mecab-Swift", package: "Mecab-Swift"),
                .product(name: "IPADic", package: "Mecab-Swift"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RubyUI",
            dependencies: ["RubyCore"],
            swiftSettings: swiftSettings + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "RubyUITests",
            dependencies: ["RubyCore", "RubyUI"],
            swiftSettings: swiftSettings + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "RubyCoreTests",
            dependencies: ["RubyCore", "RubyTransliteration"],
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
