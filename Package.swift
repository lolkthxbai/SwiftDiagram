// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "SwiftDiagram",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftDiagramModel",
            targets: ["SwiftDiagramModel"]
        ),
        .library(
            name: "SwiftDiagramCore",
            targets: ["SwiftDiagramCore"]
        ),
        .executable(
            name: "swiftdiagram",
            targets: ["swiftdiagram"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
    ],
    targets: [
        .target(name: "SwiftDiagramModel"),
        .target(name: "SwiftDiagramSyntax"),
        .target(
            name: "SwiftDiagramSyntaxParser",
            dependencies: ["SwiftDiagramSyntax"]
        ),
        .target(
            name: "SwiftDiagramParser",
            dependencies: [
                "SwiftDiagramModel",
                "SwiftDiagramSyntax",
                "SwiftDiagramSyntaxParser"
            ]
        ),
        .target(
            name: "SwiftDiagramValidation",
            dependencies: ["SwiftDiagramModel"]
        ),
        .target(
            name: "SwiftDiagramFormatter",
            dependencies: [
                "SwiftDiagramSyntax",
                "SwiftDiagramSyntaxParser"
            ]
        ),
        .target(
            name: "SwiftDiagramRendering",
            dependencies: ["SwiftDiagramModel"]
        ),
        .target(
            name: "SwiftDiagramMermaid",
            dependencies: [
                "SwiftDiagramModel",
                "SwiftDiagramRendering"
            ]
        ),
        .target(
            name: "SwiftDiagramPlantUML",
            dependencies: [
                "SwiftDiagramModel",
                "SwiftDiagramRendering"
            ]
        ),
        .target(
            name: "SwiftDiagramJSON",
            dependencies: ["SwiftDiagramModel"]
        ),
        .target(
            name: "SwiftDiagramConfiguration",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .target(
            name: "SwiftDiagramSwiftSyntax",
            dependencies: [
                "SwiftDiagramModel",
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        .target(
            name: "SwiftDiagramCore",
            dependencies: [
                "SwiftDiagramConfiguration",
                "SwiftDiagramFormatter",
                "SwiftDiagramJSON",
                "SwiftDiagramModel",
                "SwiftDiagramParser",
                "SwiftDiagramRendering",
                "SwiftDiagramSwiftSyntax",
                "SwiftDiagramValidation"
            ]
        ),
        .executableTarget(
            name: "swiftdiagram",
            dependencies: [
                "SwiftDiagramCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "SwiftDiagramModelTests",
            dependencies: ["SwiftDiagramModel"]
        )
    ],
    swiftLanguageModes: [.v6]
)
