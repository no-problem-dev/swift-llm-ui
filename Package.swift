// swift-tools-version: 6.2
import PackageDescription

// SwiftUI で書かれた表示層。ロジックは持たず、下の層が組んだ値を描くだけにする。
// 判断・計算・保管は swift-llm-client / swift-agent-runtime に置く(あちらは Linux で
// 動く)。ここは Apple 専用と割り切ることで、下の層に SwiftUI が混ざるのを防ぐ。
let package = Package(
    name: "swift-llm-ui",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LLMUI", targets: ["LLMUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/no-problem-dev/swift-llm-client.git", from: "5.1.0"),
        .package(url: "https://github.com/no-problem-dev/swift-llm-cloud.git", from: "6.0.0"),
        .package(url: "https://github.com/no-problem-dev/swift-agent-runtime.git", from: "0.20.1"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "LLMUI",
            dependencies: [
                .product(name: "LLMClient", package: "swift-llm-client"),
                .product(name: "LLMCloudBranding", package: "swift-llm-cloud"),
                .product(name: "AgentLoopKit", package: "swift-agent-runtime"),
            ]
        ),
        .testTarget(
            name: "LLMUITests",
            dependencies: ["LLMUI"]
        ),
    ]
)
