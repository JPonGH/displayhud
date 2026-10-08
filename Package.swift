// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DisplayHUD",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DisplayHUDCore", targets: ["DisplayHUDCore"]),
        .library(name: "DisplayHUDPlatform", targets: ["DisplayHUDPlatform"]),
        .executable(name: "DisplayHUD", targets: ["DisplayHUDApp"]),
    ],
    targets: [
        .target(name: "DisplayHUDCore"),
        .target(
            name: "DisplayHUDPlatform",
            dependencies: ["DisplayHUDCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "DisplayHUDApp",
            dependencies: ["DisplayHUDCore", "DisplayHUDPlatform"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "DisplayHUDCoreTests",
            dependencies: ["DisplayHUDCore"]
        ),
        .testTarget(
            name: "DisplayHUDPlatformTests",
            dependencies: ["DisplayHUDCore", "DisplayHUDPlatform"]
        ),
    ]
)
