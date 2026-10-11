// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "CLTConsumer", platforms: [.macOS(.v14)],
  dependencies: [.package(name: "BugKit", path: "../..")],
  targets: [.executableTarget(name: "CLTConsumer", dependencies: [.product(name: "BugKit", package: "BugKit")])])
