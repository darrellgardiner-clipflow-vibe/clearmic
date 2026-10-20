// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "RouteCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [
    .library(name: "RouteCore", targets: ["RouteCore"])
], targets: [
    .target(name: "RouteCore"),
    .testTarget(name: "RouteCoreTests", dependencies: ["RouteCore"])
])
