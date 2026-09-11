// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "tailclip-sync",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SyncCore"),
        .executableTarget(name: "tailclip-sync", dependencies: ["SyncCore"]),
        .executableTarget(name: "sync-check", dependencies: ["SyncCore"]),
    ]
)
