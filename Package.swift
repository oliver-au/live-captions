// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LiveCaptions",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "LiveCaptions",
            path: "Sources/LiveCaptions",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
