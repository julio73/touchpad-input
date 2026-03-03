// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "touchpad-input",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "TouchpadInputCore", targets: ["TouchpadInputCore"]),
    ],
    targets: [
        .target(
            name: "TouchpadInputCore",
            path: "Sources/TouchpadInputCore"
        ),
        .executableTarget(
            name: "TouchpadInputApp",
            dependencies: ["TouchpadInputCore"],
            path: "Sources/TouchpadInputApp"
        ),
        .testTarget(
            name: "TouchpadInputCoreTests",
            dependencies: ["TouchpadInputCore"],
            path: "Tests/TouchpadInputCoreTests"
        ),
    ]
)
