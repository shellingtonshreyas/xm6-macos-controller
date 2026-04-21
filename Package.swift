// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SonyMacApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SonyMacApp", targets: ["SonyMacApp"])
    ],
    targets: [
        .executableTarget(
            name: "SonyMacApp",
            path: "Sources/SonyMacApp"
        ),
        .testTarget(
            name: "SonyMacAppTests",
            dependencies: ["SonyMacApp"],
            path: "Tests/SonyMacAppTests"
        )
    ]
)
