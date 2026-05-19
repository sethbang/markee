// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Markee",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Markee", targets: ["Markee"]),
        .executable(name: "MarkeeQuickLookPreview", targets: ["MarkeeQuickLookPreview"]),
        .executable(name: "MarkeeQuickLookThumbnail", targets: ["MarkeeQuickLookThumbnail"]),
    ],
    targets: [
        .target(
            name: "MarkeeKit",
            path: "Sources/MarkeeKit"
        ),
        .executableTarget(
            name: "Markee",
            dependencies: ["MarkeeKit"],
            path: "Sources/Markee"
        ),
        .executableTarget(
            name: "MarkeeQuickLookPreview",
            dependencies: ["MarkeeKit"],
            path: "Sources/MarkeeQuickLookPreview"
        ),
        .executableTarget(
            name: "MarkeeQuickLookThumbnail",
            dependencies: ["MarkeeKit"],
            path: "Sources/MarkeeQuickLookThumbnail"
        ),
        .testTarget(
            name: "MarkeeKitTests",
            dependencies: ["MarkeeKit"],
            path: "Tests/MarkeeKitTests"
        ),
        .testTarget(
            name: "MarkeeTests",
            dependencies: ["Markee"],
            path: "Tests/MarkeeTests"
        ),
    ]
)
