// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WatchProtocol",
    products: [.library(name: "WatchProtocol", targets: ["WatchProtocol"])],
    targets: [
        .target(name: "WatchProtocol"),
        .testTarget(name: "WatchProtocolTests", dependencies: ["WatchProtocol"])
    ]
)
