// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "panespace",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "panespace", targets: ["panespace"]),
        .executable(name: "caps", targets: ["caps"]),
    ],
    dependencies: [
        // Auto-updates for Panespace.app, from the appcast attached to each GitHub release.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        // Pure window-management logic: tree, layout, config, commands. No AppKit, fully unit-tested.
        .target(name: "PanespaceCore"),
        // Shared by both apps: Caps Lock remap (hidutil) and the panespace IPC socket.
        .target(name: "MacKit"),
        // macOS glue: Accessibility API, event tap, IPC, menu bar.
        .executableTarget(
            name: "panespace",
            dependencies: ["PanespaceCore", "MacKit", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                // Sparkle.framework ships in Panespace.app/Contents/Frameworks (see the Makefile's `app`).
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "PanespaceCoreTests", dependencies: ["PanespaceCore"]),
        // Caps: Caps Lock as a programmable key, per app. Config parsing/resolution is pure and tested.
        .target(name: "CapsCore", dependencies: ["PanespaceCore"]),
        .executableTarget(
            name: "caps",
            dependencies: ["CapsCore", "MacKit"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]
        ),
        .testTarget(name: "CapsCoreTests", dependencies: ["CapsCore"]),
    ]
)
