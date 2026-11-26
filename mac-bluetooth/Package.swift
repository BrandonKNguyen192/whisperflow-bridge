// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WhisperBridgeBluetooth",
    platforms: [.macOS(.v14)],
    targets: [
        // Wire format (symlinked from ios-app/WhisperBridgeCore/BLEFraming.swift,
        // so both ends compile the same file) plus the receiver forwarding logic.
        .target(name: "BridgeBLECore"),
        .executableTarget(name: "WhisperBridgeBluetooth", dependencies: ["BridgeBLECore"]),
        .testTarget(name: "BridgeBLECoreTests", dependencies: ["BridgeBLECore"]),
    ]
)
