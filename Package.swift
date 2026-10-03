// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Fieldwatch",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FieldwatchCore",
            targets: ["FieldwatchCore"]
        ),
        .library(
            name: "FieldwatchUI",
            targets: ["FieldwatchUI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FieldwatchCore",
            dependencies: [],
            path: "Sources/FieldwatchCore",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "FieldwatchUI",
            dependencies: ["FieldwatchCore"],
            path: "Sources/FieldwatchUI"
        )
    ]
)
