// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Markee",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Markee", targets: ["Markee"]),
    ],
    targets: [
        .executableTarget(
            name: "Markee",
            path: "Sources/Markee"
        ),
        .testTarget(
            name: "MarkeeTests",
            dependencies: ["Markee"],
            path: "Tests/MarkeeTests"
        ),
    ]
)
