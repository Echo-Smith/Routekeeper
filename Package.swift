// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Routekeeper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Routekeeper", targets: ["Routekeeper"])],
    targets: [
        .target(name: "CAuditToken", linkerSettings: [.linkedLibrary("bsm")]),
        .target(name: "GuardCore"),
        .executableTarget(name: "Routekeeper", dependencies: ["GuardCore"]),
        .executableTarget(name: "RoutekeeperFilter", dependencies: ["GuardCore", "CAuditToken"], path: "NetworkExtension", exclude: ["Info.plist", "Filter.entitlements"]),
        .testTarget(name: "GuardCoreTests", dependencies: ["GuardCore", "Routekeeper"])
    ]
)
