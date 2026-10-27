// swift-tools-version: 6.0
import PackageDescription

// TapCore is portable (Foundation only) so the detector and rules can be built
// and tested on any platform. The TapDeck app target needs macOS.
var products: [Product] = [
    .library(name: "TapCore", targets: ["TapCore"]),
]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "TapCore"),
    .testTarget(name: "TapCoreTests", dependencies: ["TapCore"]),
]

#if os(macOS)
products.append(.executable(name: "TapDeck", targets: ["TapDeck"]))
dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"))
targets.append(
    .executableTarget(
        name: "TapDeck",
        dependencies: [
            "TapCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ],
        linkerSettings: [
            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
        ]
    )
)
#endif

let package = Package(
    name: "TapDeck",
    platforms: [
        .macOS("14.0"),
    ],
    products: products,
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v5]
)
