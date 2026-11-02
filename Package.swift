// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dafeiyu",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Dafeiyu", targets: ["Dafeiyu"])],
    targets: [
        .target(name: "DafeiyuCore"),
        .executableTarget(name: "Dafeiyu", dependencies: ["DafeiyuCore"],
                          resources: [.copy("Resources/Assets")]),
        .testTarget(name: "DafeiyuCoreTests", dependencies: ["DafeiyuCore"]),
        .testTarget(name: "DafeiyuAppTests", dependencies: ["Dafeiyu", "DafeiyuCore"])
    ],
    swiftLanguageModes: [.v5]
)
