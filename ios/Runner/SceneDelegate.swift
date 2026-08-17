import UIKit
import Flutter

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else {
      return
    }

    let window = UIWindow(windowScene: windowScene)
#if DEBUG && !targetEnvironment(simulator)
    window.rootViewController = DebugBlockedViewController()
#else
    let controller = FlutterViewController(project: nil, nibName: nil, bundle: nil)
    GeneratedPluginRegistrant.register(with: controller)
    MediaChannel.register(with: controller)
    window.rootViewController = controller
    if let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate {
      appDelegate.window = window
    }
#endif
    window.makeKeyAndVisible()
    self.window = window
  }
}

#if DEBUG && !targetEnvironment(simulator)
private final class DebugBlockedViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(red: 0.043, green: 0.051, blue: 0.071, alpha: 1)

    let title = UILabel()
    title.text = "请改用 Profile 运行"
    title.textColor = .white
    title.font = .boldSystemFont(ofSize: 22)
    title.textAlignment = .center

    let body = UILabel()
    body.text = "当前 iOS 不允许 Flutter Debug（JIT），所以会 mprotect 崩溃。\n\n请在电脑终端执行：\n\nfvm flutter run --profile -d ios"
    body.textColor = UIColor(white: 0.72, alpha: 1)
    body.font = .systemFont(ofSize: 16)
    body.numberOfLines = 0
    body.textAlignment = .center

    let stack = UIStackView(arrangedSubviews: [title, body])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }
}
#endif
