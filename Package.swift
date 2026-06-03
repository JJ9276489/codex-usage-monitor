// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexUsageMonitor", targets: ["CodexUsageMonitor"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CodexUsageMonitor",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
