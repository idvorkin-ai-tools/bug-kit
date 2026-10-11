import Foundation

/// Shared root for default reports, session logs and crash evidence. Explicit caller paths take precedence.
public enum BugStorage {
  /// macOS uses Application Support/<bundle ID>, or the executable name for an unbundled command-line app.
  /// iOS and watchOS keep their app-container Documents layout for the device listener.
  public static var defaultDirectory: URL {
    #if os(macOS)
      return macDirectory(
        applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        bundleIdentifier: Bundle.main.bundleIdentifier, processName: ProcessInfo.processInfo.processName)
    #else
      return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    #endif
  }

  static func macDirectory(applicationSupport: URL, bundleIdentifier: String?, processName: String) -> URL {
    let identity = bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? processName
    // Keep the chosen identity one directory component, even for an unusually named executable.
    let safe = identity.unicodeScalars.map { scalar -> String in
      CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar) ? String(scalar) : "-"
    }.joined()
    let name = safe.isEmpty || safe == "." || safe == ".." ? "BugKit" : safe
    return applicationSupport.appendingPathComponent(name, isDirectory: true)
  }
}
