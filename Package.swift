// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MagSafeDark",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MagSafeCore", targets: ["MagSafeCore"]),
        .executable(name: "MagSafeDark", targets: ["MagSafeDark"]),
        .executable(name: "magsafe-led-helper", targets: ["SMCHelperCLI"]),
        .executable(name: "magsafe-led-daemon", targets: ["SMCDaemon"]),
        .executable(name: "magsafe-led-client", targets: ["SMCClient"]),
        .executable(name: "magsafe-scheduler", targets: ["MagSafeScheduler"]),
        .executable(name: "magsafe-schedule-editor", targets: ["ScheduleEditor"])
    ],
    targets: [
        .target(name: "SMCHelper", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "MagSafeCore"),
        .executableTarget(name: "SMCHelperCLI", dependencies: ["SMCHelper"]),
        .executableTarget(name: "SMCDaemon", dependencies: ["SMCHelper"]),
        .executableTarget(name: "SMCClient"),
        .executableTarget(name: "MagSafeScheduler", dependencies: ["MagSafeCore"]),
        .executableTarget(name: "ScheduleEditor", dependencies: ["MagSafeCore"]),
        .executableTarget(name: "MagSafeDark", dependencies: ["MagSafeCore"])
    ]
)
