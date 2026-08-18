// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TravelTime",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TravelTime",
            path: "Sources/TravelTime"
        ),
        .testTarget(
            name: "TravelTimeTests",
            dependencies: ["TravelTime"],
            path: "Tests/TravelTimeTests"
        )
    ]
)
