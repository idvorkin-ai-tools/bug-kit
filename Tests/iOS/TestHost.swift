import UIKit

// UIApplication dispatches UIControl target actions; a hostless logic-test runner cannot exercise them.
@main
final class DiagnosticsAppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: "Diagnostics", sessionRole: session.role)
    configuration.delegateClass = DiagnosticsSceneDelegate.self
    return configuration
  }
}

final class DiagnosticsSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    self.window = window
  }
}
