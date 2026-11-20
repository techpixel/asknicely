// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AskNicely",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AskNicely",
            resources: [.process("Resources")]
        )
    ]
)
