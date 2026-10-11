// swift-tools-version: 6.2

import PackageDescription

// Approachable concurrency, as in new Xcode projects, in the Swift 6 language
// mode, which already has the rest of it. RubyUI also isolates to the main
// actor by default; RubyCore, RubyMeCab and RubyTransliteration are plain
// data and stay nonisolated.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "RubyText",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0")],
    products: [
        /// Kana to romaji, hiragana to katakana and back, with no
        /// dictionary and only the standard library.
        .library(name: "RubyTransliteration", targets: ["RubyTransliteration"]),
        /// Readings as plain data: analysis, markup, dictionary lookups,
        /// with whichever analyzer you give it.
        .library(name: "RubyCore", targets: ["RubyCore"]),
        /// An analyzer using MeCab and a dictionary in IPAdic's format,
        /// which you supply.
        .library(name: "RubyMeCab", targets: ["RubyMeCab"]),
        /// SwiftUI views that draw furigana and romaji.
        .library(name: "RubyUI", targets: ["RubyUI"]),
    ],
    traits: [
        // On by default, so nothing changes for apps that use RubyMeCab. An
        // app that doesn't can depend on RubyText with `traits: []`, and
        // SwiftPM never downloads Mecab-Swift and its dictionaries.
        .trait(
            name: "MeCab",
            description: "RubyMeCab, the MeCab analyzer, with Mecab-Swift and its IPAdic dictionary."
        ),
        .default(enabledTraits: ["MeCab"]),
    ],
    dependencies: [
        // Only fetched when the MeCab trait is on.
        .package(url: "https://github.com/shinjukunian/Mecab-Swift", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "RubyTransliteration",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RubyCore",
            dependencies: ["RubyTransliteration"],
            // Part-of-speech names, in 16 languages and English.
            resources: [.process("Localizable.xcstrings")],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RubyMeCab",
            dependencies: [
                "RubyCore",
                "RubyTransliteration",
                .product(name: "Mecab-Swift", package: "Mecab-Swift", condition: .when(traits: ["MeCab"])),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RubyUI",
            dependencies: ["RubyCore", "RubyTransliteration"],
            // Word details, VoiceOver hints and errors, in 16 languages
            // and English.
            resources: [.process("Localizable.xcstrings")],
            swiftSettings: swiftSettings + [.defaultIsolation(MainActor.self)]
        ),
        // Precomputes speech recognition for a narration recording:
        // swift run align-narration <recording>
        .executableTarget(
            name: "align-narration",
            dependencies: ["RubyUI"],
            path: "Tools",
            exclude: ["build-dictionary.py"],
            sources: ["align-narration.swift"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RubyUITests",
            dependencies: [
                "RubyCore",
                "RubyMeCab",
                "RubyTransliteration",
                "RubyUI",
                // Apps bundle their own dictionary; tests read with this one.
                .product(name: "IPADic", package: "Mecab-Swift", condition: .when(traits: ["MeCab"])),
            ],
            swiftSettings: swiftSettings + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "RubyCoreTests",
            dependencies: [
                "RubyCore",
                "RubyMeCab",
                "RubyTransliteration",
                // Apps bundle their own dictionary; tests read with this one.
                .product(name: "IPADic", package: "Mecab-Swift", condition: .when(traits: ["MeCab"])),
            ],
            // A few JMdict entries for the dictionary tests.
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RubyTransliterationTests",
            dependencies: ["RubyTransliteration"],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
