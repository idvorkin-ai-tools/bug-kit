// swift-tools-version:5.10
// BugKit: one bug-report library for every iOS app. The model, the store and the dialog's flow build on macOS too,
// so `swift test` runs on the host in about a second; the UI (shake, sheet, presenter) is iOS only.

import PackageDescription

let package = Package(
  name: "BugKit",
  platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
  products: [.library(name: "BugKit", targets: ["BugKit"])],
  targets: [
    .target(name: "BugKit"),
    .testTarget(name: "BugKitTests", dependencies: ["BugKit"]),
  ]
)
