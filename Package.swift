// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MP4ToOGV",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MP4ToOGV", targets: ["MP4ToOGV"])],
    targets: [.executableTarget(name: "MP4ToOGV")]
)
