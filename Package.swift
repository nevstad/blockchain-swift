// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BlockchainSwift",
    platforms: [
        .macOS(.v10_14),
        .iOS(.v10)
    ],
    products: [
        .library(
            name: "BlockchainSwift",
            targets: ["BlockchainSwift"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "4.0.1")
    ],
    targets: [
        .target(
            name: "BlockchainSwift",
            dependencies: ["NIO", "GRDB"]),
        .testTarget(
            name: "BlockchainSwiftTests",
            dependencies: ["BlockchainSwift"]),
    ]
)
