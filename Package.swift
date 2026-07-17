// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Verse",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "Verse",
            path: "Sources/Verse",
            swiftSettings: [
                // AppKit delegate + Carbon callbacks; strict concurrency is
                // noise here. Revisit when the app grows.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
