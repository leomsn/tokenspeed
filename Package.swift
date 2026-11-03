// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TokenSpeed",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TokenSpeed",
            path: "Sources/TokenSpeed",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 测试直接 @testable import 可执行目标（SwiftPM 会为测试把源码编成模块），
        // 这样就不必为了可测性把源码拆成库目标、也不必给内部类型加 public。
        .testTarget(
            name: "TokenSpeedTests",
            dependencies: ["TokenSpeed"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
