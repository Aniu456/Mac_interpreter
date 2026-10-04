// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "WeChatInterpreter",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "WeChatInterpreter", targets: ["WeChatInterpreter"])],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.15.4")],
    targets: [
        .executableTarget(name: "WeChatInterpreter", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "WeChatInterpreterTests", dependencies: ["WeChatInterpreter"]),
    ],
    swiftLanguageModes: [.v6]
)
