// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FriendTranslator",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "FriendTranslator", targets: ["FriendTranslator"])],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.4")],
    targets: [
        .executableTarget(name: "FriendTranslator", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "FriendTranslatorTests", dependencies: ["FriendTranslator"]),
    ],
    swiftLanguageModes: [.v6]
)
