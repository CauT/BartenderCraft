// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BartenderCraft",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BartenderCraft", targets: ["BarGarden"])],
    targets: [
        .target(name: "BarGardenCore"),
        .executableTarget(name: "BarGarden", dependencies: ["BarGardenCore"]),
        .executableTarget(name: "BarGardenCoreChecks", dependencies: ["BarGardenCore"], path: "Tests/BarGardenCoreTests")
    ]
)
