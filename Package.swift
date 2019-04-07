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
    ],
    targets: [
        .target(
            name: "BlockchainSwift",
            dependencies: []),
        .testTarget(
            name: "BlockchainSwiftTests",
            dependencies: ["BlockchainSwift"]),
    ]
)
