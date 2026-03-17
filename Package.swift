// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CroPDFMacOS",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "CroPDFMacOS",
            path: "src",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
