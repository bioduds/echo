import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var fullscreenObserver: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Force immersive mode: start fullscreen and keep the app there.
    self.collectionBehavior.insert(.fullScreenPrimary)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    DispatchQueue.main.async {
      if !self.styleMask.contains(.fullScreen) {
        self.toggleFullScreen(nil)
      }
    }

    fullscreenObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didExitFullScreenNotification,
      object: self,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      DispatchQueue.main.async {
        if !self.styleMask.contains(.fullScreen) {
          self.toggleFullScreen(nil)
        }
      }
    }

    super.awakeFromNib()
  }

  deinit {
    if let fullscreenObserver {
      NotificationCenter.default.removeObserver(fullscreenObserver)
    }
  }
}
