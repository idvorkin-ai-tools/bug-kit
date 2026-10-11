/// Mac Team Development profiles omit the environment entitlement. Distribution readers must supply it
/// explicitly before preflight can attest that they target Production.
func cloudKitEnvironmentMatches(_ entitlements: [String: Any], expected: String?) -> Bool {
  guard let expected else { return true }
  guard expected == "Development" || expected == "Production" else { return false }
  guard let value = entitlements["com.apple.developer.icloud-container-environment"] else {
    return expected == "Development"
  }
  return value as? String == expected
}
