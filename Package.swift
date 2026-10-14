// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DevApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DevApp", targets: ["DevApp"])
    ],
    dependencies: [
        // Gerçek PTY tabanlı terminal emülatörü (AppKit NSView)
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.20.0")
    ],
    targets: [
        .executableTarget(
            name: "DevApp",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/DevApp"
        )
    ]
)
