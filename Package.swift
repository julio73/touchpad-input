// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TouchpadInputMVP",
    platforms: [.macOS(.v11)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TouchpadInputMVP",
            path: "Sources/TouchpadInputMVP"
        )
    ]
)

