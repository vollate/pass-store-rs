import Flutter
import UIKit

@objc class SceneDelegate: FlutterSceneDelegate {
  private weak var connectedWindowScene: UIWindowScene?
  private var privacyCover: UIView?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    connectedWindowScene = scene as? UIWindowScene
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(captureStateChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil)
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    showPrivacyCover()
    super.sceneWillResignActive(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    if !UIScreen.main.isCaptured {
      hidePrivacyCover()
    }
    super.sceneDidBecomeActive(scene)
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    NotificationCenter.default.removeObserver(self)
    privacyCover = nil
    connectedWindowScene = nil
    super.sceneDidDisconnect(scene)
  }

  @objc private func captureStateChanged() {
    if UIScreen.main.isCaptured {
      showPrivacyCover()
    } else if connectedWindowScene?.activationState == .foregroundActive {
      hidePrivacyCover()
    }
  }

  private func showPrivacyCover() {
    guard privacyCover == nil, let window = sceneWindow else { return }
    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = .systemBackground

    let symbol = UIImageView(image: UIImage(systemName: "lock.shield"))
    symbol.tintColor = .label
    symbol.contentMode = .scaleAspectFit
    symbol.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(symbol)
    NSLayoutConstraint.activate([
      symbol.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      symbol.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
      symbol.widthAnchor.constraint(equalToConstant: 64),
      symbol.heightAnchor.constraint(equalToConstant: 64),
    ])
    window.addSubview(cover)
    privacyCover = cover
  }

  private func hidePrivacyCover() {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }

  private var sceneWindow: UIWindow? {
    guard let windowScene = connectedWindowScene else { return nil }
    return windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
  }
}
