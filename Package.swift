// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RecordCompareIOS",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .executableTarget(
            name: "RecordCompareIOS",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
            path: "Sources/RecordCompareIOS"
        )
    ]
)
