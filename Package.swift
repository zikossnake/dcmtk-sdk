// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DCMTKSDK",
    products: [
        .library(name: "DCMTK", targets: ["DCMTK"]),
    ],
    targets: [
        .binaryTarget(name: "DCMTK", path: "DCMTK.xcframework"),
    ]
)
