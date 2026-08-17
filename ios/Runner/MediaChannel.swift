import Photos
import AVKit
import Flutter
import UIKit

enum MediaChannel {
  static let name = "media_downloader/media"
  private static weak var host: UIViewController?

  static func register(with controller: FlutterViewController) {
    host = controller
    let channel = FlutterMethodChannel(
      name: name,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
        if call.method == "saveToPhotos" || call.method == "openPreview" {
          result(FlutterError(code: "bad_args", message: "缺少文件路径", details: nil))
          return
        }
        result(FlutterMethodNotImplemented)
        return
      }
      if call.method == "saveToPhotos" {
        saveToPhotos(path: path, result: result)
        return
      }
      if call.method == "openPreview" {
        openPreview(path: path, result: result)
        return
      }
      result(FlutterMethodNotImplemented)
    }
  }

  private static func presenter() -> UIViewController? {
    var top = host
    while let next = top?.presentedViewController {
      top = next
    }
    return top
  }

  private static func openPreview(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "missing", message: "文件不存在", details: nil))
      return
    }
    let ext = url.pathExtension.lowercased()
    DispatchQueue.main.async {
      guard let host = presenter() else {
        result(FlutterError(code: "ui", message: "无法打开播放器", details: nil))
        return
      }
      if ["mp4", "mov", "m4v", "m4a"].contains(ext) {
        let controller = VideoPreviewController(url: url)
        controller.modalPresentationStyle = .fullScreen
        host.present(controller, animated: true)
        result(true)
        return
      }
      let image = UIImage(contentsOfFile: path)
      let controller = ImagePreviewController(image: image, titleText: url.lastPathComponent)
      controller.modalPresentationStyle = .fullScreen
      host.present(controller, animated: true)
      result(true)
    }
  }

  private static func saveToPhotos(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    let ext = url.pathExtension.lowercased()
    let isVideo = ["mp4", "mov", "m4v"].contains(ext)
    let isImage = ["jpg", "jpeg", "png", "gif", "heic", "webp"].contains(ext)
    guard isVideo || isImage else {
      result(FlutterError(code: "unsupported", message: "不支持保存该类型", details: nil))
      return
    }

    let handler: (PHAuthorizationStatus) -> Void = { status in
      guard MediaChannel.isPhotosAllowed(status) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "denied", message: "没有相册权限", details: nil))
        }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        if isVideo {
          PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } else {
          PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }
      }, completionHandler: { ok, error in
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
          } else {
            result(ok)
          }
        }
      })
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: handler)
    } else {
      PHPhotoLibrary.requestAuthorization(handler)
    }
  }

  private static func isPhotosAllowed(_ status: PHAuthorizationStatus) -> Bool {
    if status == .authorized {
      return true
    }
    if #available(iOS 14, *) {
      return status == .limited
    }
    return false
  }
}

private final class VideoPreviewController: UIViewController {
  private let player: AVPlayer
  private let playerController = AVPlayerViewController()

  init(url: URL) {
    player = AVPlayer(url: url)
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    playerController.player = player
    playerController.showsPlaybackControls = true
    addChild(playerController)
    playerController.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(playerController.view)
    playerController.didMove(toParent: self)

    let close = UIButton(type: .system)
    close.setTitle("关闭", for: .normal)
    close.setTitleColor(.white, for: .normal)
    close.titleLabel?.font = .boldSystemFont(ofSize: 17)
    close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    close.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(close)

    NSLayoutConstraint.activate([
      playerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      playerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      playerController.view.topAnchor.constraint(equalTo: view.topAnchor),
      playerController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    player.play()
  }

  @objc private func closeTapped() {
    player.pause()
    dismiss(animated: true)
  }
}

private final class ImagePreviewController: UIViewController {
  private let image: UIImage?
  private let titleText: String

  init(image: UIImage?, titleText: String) {
    self.image = image
    self.titleText = titleText
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    let imageView = UIImageView(image: image)
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(imageView)

    let close = UIButton(type: .system)
    close.setTitle("关闭", for: .normal)
    close.setTitleColor(.white, for: .normal)
    close.titleLabel?.font = .boldSystemFont(ofSize: 17)
    close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    close.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(close)

    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 48),
      imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
    ])
  }

  @objc private func closeTapped() {
    dismiss(animated: true)
  }
}
