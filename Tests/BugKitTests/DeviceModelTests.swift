import Foundation
import Testing

@testable import BugKit

@Suite struct DeviceModelTests {
  @Test func phoneKeepsItsMachine() {
    #expect(BugAppInfo.model(machine: "iPhone18,1", hwModel: "D94AP", simulatorModel: nil) == "iPhone18,1")
  }

  @Test func macUsesHwModelWhenMachineIsOnlyTheCPU() {
    #expect(BugAppInfo.model(machine: "arm64", hwModel: "Mac16,12", simulatorModel: nil) == "Mac16,12")
    #expect(BugAppInfo.model(machine: "x86_64", hwModel: "MacBookPro16,1", simulatorModel: nil) == "MacBookPro16,1")
    #expect(BugAppInfo.model(machine: "arm64", hwModel: nil, simulatorModel: nil) == "arm64")
  }

  @Test func simulatorNamesTheSimulatedModel() {
    #expect(BugAppInfo.model(machine: "arm64", hwModel: "Mac16,12", simulatorModel: "iPhone17,1") == "iPhone17,1")
    #expect(BugAppInfo.model(machine: "arm64", hwModel: "Mac16,12", simulatorModel: "") == "Mac16,12")
  }

  #if os(macOS)
    @Test func thisMacIsNamedByItsModel() {
      let model = BugAppInfo.hardwareModel()
      #expect(!["arm64", "x86_64"].contains(model))
      #expect(model.contains("Mac"))
    }
  #endif
}
