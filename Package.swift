// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UniversalControlAndroid",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "UniversalControlAndroid", targets: ["MacApp"])],
    targets: [
        .systemLibrary(name: "CLibUSB", pkgConfig: "libusb-1.0", providers: [.brew(["libusb"])]),
        .target(name: "CAccessory", dependencies: ["CLibUSB"]),
        .target(name: "ControlCore"),
        .target(name: "CVirtualDisplay", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("Foundation")]),
        .executableTarget(name: "MacApp", dependencies: ["ControlCore", "CAccessory", "CVirtualDisplay"]),
        .executableTarget(name: "CoreChecks", dependencies: ["ControlCore"], path: "Tests/ControlCoreTests")
    ]
)
