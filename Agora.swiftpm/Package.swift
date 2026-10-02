// swift-tools-version: 5.9

// Swift Playgrounds app package. Swift Playgrounds rewrites this file when the app settings are changed in the
// app (name, icon, version); the source layout (all folders of this package) stays as it is.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Agora",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Agora",
            targets: ["AppModule"],
            bundleIdentifier: "org.agora.app",
            teamIdentifier: "",
            displayVersion: "1.0.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .leaf),
            accentColor: .presetColor(.cyan),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
