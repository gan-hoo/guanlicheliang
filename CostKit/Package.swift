// swift-tools-version:5.9
import PackageDescription

// 费用与油耗计算（纯 Foundation，可单独测试）：swift test --package-path CostKit
let package = Package(
    name: "CostKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CostKit", targets: ["CostKit"])
    ],
    targets: [
        .target(name: "CostKit"),
        .testTarget(name: "CostKitTests", dependencies: ["CostKit"])
    ]
)
