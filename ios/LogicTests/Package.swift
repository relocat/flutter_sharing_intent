// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FSILogic",
    targets: [
        .target(name: "FSILogic", path: "Sources/FSILogic"),
        .testTarget(name: "FSILogicTests", dependencies: ["FSILogic"], path: "Tests/FSILogicTests"),
    ]
)
