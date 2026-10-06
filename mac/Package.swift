// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "sctmp3app",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "sctmp3app",
            path: "Sources/sctmp3app"
        )
    ]
)
