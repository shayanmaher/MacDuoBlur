// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDuoBlur",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacDuoBlur", targets: ["MacDuoBlur"])
    ],
    targets: [
        .executableTarget(
            name: "MacDuoBlur",
            path: "Sources/MacDuoBlur"
        )
    ]
)
