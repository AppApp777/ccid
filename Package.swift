// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ccid",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ccid", targets: ["ccid"]),
        .executable(name: "CCIDApp", targets: ["CCIDApp"]),
        .library(name: "CCIDCore", targets: ["CCIDCore"]),
    ],
    targets: [
        .target(name: "CCIDCore"),
        .executableTarget(name: "ccid", dependencies: ["CCIDCore"]),
        .executableTarget(
            name: "CCIDApp",
            dependencies: ["CCIDCore"],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("ServiceManagement")]
        ),
        .testTarget(name: "CCIDCoreTests", dependencies: ["CCIDCore"]),
    ]
)
