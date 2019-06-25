// swift-tools-version:5.1
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
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "4.0.1")
    ],
    targets: [
        .target(
            name: "BlockchainSwift",
            dependencies: ["Logging", "NIO", "GRDB"]),
        .testTarget(
            name: "BlockchainSwiftTests",
            dependencies: ["BlockchainSwift"]),
    ]
)
