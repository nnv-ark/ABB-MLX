// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ABB-MLX",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ABBMLXCore", targets: ["ABBMLXCore"]),
        .library(name: "ABBMLXServer", targets: ["ABBMLXServer"]),
        .executable(name: "ABBMLXApp", targets: ["ABBMLXApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.2"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.21.2"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.5.0"),
    ],
    targets: [
        .target(
            name: "ABBMLXCore",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                .product(name: "MLXEmbedders", package: "mlx-swift-examples"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
            ]
        ),
        .target(
            name: "ABBMLXServer",
            dependencies: [
                "ABBMLXCore",
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .executableTarget(
            name: "ABBMLXApp",
            dependencies: ["ABBMLXServer", "ABBMLXCore"],
            exclude: ["Resources/Info.plist"]
        ),
    ]
)
