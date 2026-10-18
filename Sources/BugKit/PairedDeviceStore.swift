// Story 040: where the paired device is kept. One Keychain item, this device only, in an access group every app of
// Igor's team names in its `keychain-access-groups` entitlement, so pairing in one app pairs them all, and Unpair in
// one unpairs them all.

import Foundation
import Security

public protocol PairedDeviceStore: AnyObject {
  func load() -> PairedDevice?
  func save(_ device: PairedDevice) throws
  func remove()
}

/// The Keychain refused the paired device: the call and its status.
public struct PairedDeviceStoreFailed: Error, CustomStringConvertible {
  public let status: OSStatus
  public var description: String { "SecItemAdd \(status)" }
}

public final class KeychainPairedDeviceStore: PairedDeviceStore {
  private let query: [String: Any]

  /// `accessGroup` is the shared group with the team prefix, as `ABCDE12345.com.idvorkin.paired-device`; nil keeps
  /// the item in the app's own group (a simulator build without the entitlement).
  public init(accessGroup: String?) {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.idvorkin.paired-device",
      kSecAttrAccount as String: "device",
    ]
    query[kSecAttrAccessGroup as String] = accessGroup
    self.query = query
  }

  public func load() -> PairedDevice? {
    var item: CFTypeRef?
    var lookup = query
    lookup[kSecReturnData as String] = true
    guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return try? JSONDecoder().decode(PairedDevice.self, from: data)
  }

  public func save(_ device: PairedDevice) throws {
    SecItemDelete(query as CFDictionary)
    var item = query
    item[kSecValueData as String] = try JSONEncoder().encode(device)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    if status != errSecSuccess { throw PairedDeviceStoreFailed(status: status) }
  }

  public func remove() { SecItemDelete(query as CFDictionary) }
}

/// Keeps the device in memory: for tests, and for previews.
public final class MemoryPairedDeviceStore: PairedDeviceStore {
  private var device: PairedDevice?
  public init(_ device: PairedDevice? = nil) { self.device = device }
  public func load() -> PairedDevice? { device }
  public func save(_ device: PairedDevice) throws { self.device = device }
  public func remove() { device = nil }
}
