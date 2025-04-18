// swift-tools-version:5.7
import PackageDescription

let package = Package(
  name: "FormbricksSDK",
  platforms: [
   .iOS(.v16)
  ],
  products: [
    .library(
      name: "FormbricksSDK",
      targets: ["FormbricksSDK"]
    )
  ],
  targets: [
    .target(
      name: "FormbricksSDK",
      path: "Sources/FormbricksSDK"
    ),
    .testTarget(
      name: "FormbricksSDKTests",
      dependencies: ["FormbricksSDK"],
      path: "Tests/FormbricksSDKTests"
    )
  ]
)
