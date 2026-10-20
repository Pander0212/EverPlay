// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EverPlay",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "EverPlayCore", targets: ["EverPlayCore"])],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3")
    ],
    targets: [
        .target(name: "EverPlayCore", dependencies: [
            "ZIPFoundation", .product(name: "Crypto", package: "swift-crypto")
        ]),
        .testTarget(name: "EverPlayCoreTests", dependencies: ["EverPlayCore", "ZIPFoundation"])
    ]
)
