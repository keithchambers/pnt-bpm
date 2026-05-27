// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "pnt-cli",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "pnt-cli", targets: ["PntCLI"]),
        .library(name: "PntCliCore", targets: ["PntCliCore"])
    ],
    targets: [
        .target(
            name: "PntCliCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox")
            ]
        ),
        .executableTarget(
            name: "PntCLI",
            dependencies: ["PntCliCore"]
        ),
        .testTarget(
            name: "PntCliCoreTests",
            dependencies: ["PntCliCore"]
        )
    ]
)
