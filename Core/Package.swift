// swift-tools-version: 6.0
import PackageDescription

// QuickieCore is the platform-agnostic heart of Quickie: the Action model,
// the Provider engine, the forgiving matcher, and the SearchEngine that turns
// a typed query into a ranked Result list. It depends on nothing but the
// standard library + Foundation, so its behavior is unit-tested with
// `swift test` on any platform — no Xcode or simulator required.
let package = Package(
    name: "QuickieCore",
    products: [
        .library(name: "QuickieCore", targets: ["QuickieCore"]),
    ],
    targets: [
        .target(name: "QuickieCore"),
        .testTarget(
            name: "QuickieCoreTests",
            dependencies: ["QuickieCore"]
        ),
    ]
)
