// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MisarMail",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "MisarMail",
            targets: ["MisarMail"]
        ),
    ],
    targets: [
        .target(
            name: "MisarMail",
            path: "Sources/MisarMail"
        ),
        .testTarget(
            name: "MisarMailTests",
            dependencies: ["MisarMail"],
            path: "Tests/MisarMailTests"
        ),
    ]
)
