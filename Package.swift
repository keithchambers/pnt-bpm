// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SeratoPitchNTimeCLI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "pnt-bpm", targets: ["PntBpmCLI"]),
        .library(name: "PntBpmCore", targets: ["PntBpmCore"])
    ],
    targets: [
        .target(
            name: "PntBpmCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox")
            ]
        ),
        .executableTarget(
            name: "PntBpmCLI",
            dependencies: ["PntBpmCore"]
        ),
        .testTarget(
            name: "PntBpmCoreTests",
            dependencies: ["PntBpmCore"]
        )
    ]
)
