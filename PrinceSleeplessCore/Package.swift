// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PrinceSleeplessCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PrinceSleeplessCore", targets: ["PrinceSleeplessCore"])
    ],
    targets: [
        .target(name: "PrinceSleeplessCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "print-requirement",
            dependencies: ["PrinceSleeplessCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "PrinceSleeplessCoreTests", dependencies: ["PrinceSleeplessCore"])
    ]
)
