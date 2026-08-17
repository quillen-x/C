import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1280, height: 768))
    self.minSize = NSSize(width: 980, height: 640)
    self.title = "C"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
