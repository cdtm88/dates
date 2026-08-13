// swift-tools-version: 5.9
import PackageDescription

// DatesKit holds every rule the app can be wrong about: annual-date maths, offset
// resolution, list ordering, and notification planning. It depends on Foundation only,
// so the whole suite runs on any Swift toolchain without Xcode or a simulator.
let package = Package(
    name: "DatesKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DatesKit", targets: ["DatesKit"])
    ],
    targets: [
        .target(name: "DatesKit"),
        .testTarget(name: "DatesKitTests", dependencies: ["DatesKit"]),
    ]
)
