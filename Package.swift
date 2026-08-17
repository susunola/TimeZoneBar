// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimeZoneBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TimeZoneBar",
            path: "Sources/TimeZoneBar"
        )
    ]
)
