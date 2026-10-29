// swift-tools-version:6.0
import Foundation
import PackageDescription

// Embedding Info.plist gives the command-line binary a camera usage description.
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/gaze-switch/Info.plist")
    .path

let package = Package(
    name: "gaze-switch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GazeSwitchCore"),
        .executableTarget(
            name: "gaze-switch",
            dependencies: ["GazeSwitchCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist]),
            ]
        ),
        .testTarget(name: "GazeSwitchCoreTests", dependencies: ["GazeSwitchCore"]),
    ],
    swiftLanguageModes: [.v5]
)
