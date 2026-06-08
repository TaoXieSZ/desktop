// swift-tools-version: 5.9

import PackageDescription
let package = Package(
    name: "AhaKeyConfig",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .executable(name: "AhaKeyConfig", targets: ["AhaKeyConfig"]),
        .executable(name: "ahakeyconfig-agent", targets: ["AhaKeyConfigAgent"]),
        .executable(name: "AhaKeyWebBridgeHelper", targets: ["AhaKeyWebBridgeHelper"]),
        .executable(name: "ahakeyd", targets: ["AhaKeyDaemon"]),
        .library(name: "AhaKeyCore", targets: ["AhaKeyCore"]),
    ],
    
    targets: [
        .executableTarget(
            name: "AhaKeyConfig",
            path: "Sources",
            exclude: ["Agent", "WebBridgeHelper", "AhaKeyCore", "AhaKeyDaemon"],
            // 与 scripts/build.sh 中 Info.plist 一致。嵌入 __info_plist 段后 TCC 可识别。
            // Debug 使用单独 plist：系统在「隐私与安全性」列表中显示为「AhaKey Studio（调试）」，与正式包区分。
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Packaging/AhaKeyConfig-EmbeddedInfo-Debug.plist",
                ], .when(platforms: [.macOS], configuration: .debug)),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Packaging/AhaKeyConfig-EmbeddedInfo.plist",
                ], .when(platforms: [.macOS], configuration: .release)),
            ]
        ),
        .executableTarget(
            name: "AhaKeyConfigAgent",
            path: "Sources/Agent",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Packaging/AhaKeyAgent-EmbeddedInfo.plist",
                ], .when(platforms: [.macOS])),
            ]
        ),
        .executableTarget(
            name: "AhaKeyWebBridgeHelper",
            path: "Sources/WebBridgeHelper"
        ),
        .target(
            name: "AhaKeyCore",
            path: "Sources/AhaKeyCore"
        ),
        .executableTarget(
            name: "AhaKeyDaemon",
            dependencies: ["AhaKeyCore"],
            path: "Sources/AhaKeyDaemon"
        ),
    ]
)
