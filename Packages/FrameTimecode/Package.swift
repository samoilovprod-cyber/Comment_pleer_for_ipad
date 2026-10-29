// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FrameTimecode",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FrameTimecode", targets: ["FrameTimecode"]),
    ],
    targets: [
        .target(name: "FrameTimecode"),
        .testTarget(name: "FrameTimecodeTests", dependencies: ["FrameTimecode"]),
    ]
)
