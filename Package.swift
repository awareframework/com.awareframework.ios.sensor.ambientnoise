// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "com.awareframework.ios.sensor.ambientnoise",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "com.awareframework.ios.sensor.ambientnoise",
            targets: [
                "com.awareframework.ios.sensor.ambientnoise"
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/awareframework/com.awareframework.ios.core.git", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "com.awareframework.ios.sensor.ambientnoise",
            dependencies: [
                .product(name: "com.awareframework.ios.core", package: "com.awareframework.ios.core", condition: .when(platforms: [.iOS]))
            ],
            path: "Sources/com.awareframework.ios.sensor.ambientnoise"
        ),
        .testTarget(
            name: "com.awareframework.ios.sensor.ambientnoiseTests",
            dependencies: [
                "com.awareframework.ios.core",
                "com.awareframework.ios.sensor.ambientnoise"
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
