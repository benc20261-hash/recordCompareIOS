// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RecordCompareIOS",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "RecordCompareIOS",
            targets: ["RecordCompareIOS"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RecordCompareIOS",
            path: "Sources/RecordCompareIOS"
        )
    ]
)
