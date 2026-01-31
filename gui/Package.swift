// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GravityRename",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GravityRename", targets: ["GravityRename"])
    ],
    targets: [
        .executableTarget(
            name: "GravityRename",
            path: "GravityRename",
            resources: [
                .process("gravity-cli")
            ]
        )
    ]
)
