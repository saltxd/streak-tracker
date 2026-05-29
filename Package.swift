// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StreakTracker",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure, UI-free logic — fully unit-tested.
        .target(name: "StreakKit"),
        // The menu bar app (SwiftUI MenuBarExtra). Bundled into an .app by build.sh.
        .executableTarget(
            name: "StreakTracker",
            dependencies: ["StreakKit"]
        ),
        // Runnable logic checks: `swift run StreakKitCheck`. A plain executable rather
        // than a testTarget because XCTest/Testing aren't available under Command Line
        // Tools alone — this runs anywhere the toolchain does.
        .executableTarget(
            name: "StreakKitCheck",
            dependencies: ["StreakKit"]
        ),
    ]
)
