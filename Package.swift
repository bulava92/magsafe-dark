// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MagSafeDark",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MagSafeDark", targets: ["MagSafeDark"]),
        .executable(name: "magsafe-led-helper", targets: ["SMCHelperCLI"])
    ],
    targets: [
        .target(name: "SMCHelper", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "SMCHelperCLI", dependencies: ["SMCHelper"]),
        .executableTarget(name: "MagSafeDark", dependencies: [])
    ]
)
