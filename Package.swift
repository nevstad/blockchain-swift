// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BlockchainSwift",
    products: [
        .library(
            name: "BlockchainSwift",
            targets: ["BlockchainSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "BlockchainSwift",
            dependencies: ["NIO"]),
        .testTarget(
            name: "BlockchainSwiftTests",
            dependencies: ["BlockchainSwift"]),
    ]
)
