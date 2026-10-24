import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 桌面版按 1200x800 开窗（和 Windows 浏览器预览的常用尺寸接近），
    // 小屏至少留 900x600，避免仪表盘三栏挤成一列。
    let targetSize = NSSize(width: 1200, height: 800)
    let screenFrame = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    var frame = self.frame
    if let visible = screenFrame {
      frame.size.width = min(targetSize.width, visible.width)
      frame.size.height = min(targetSize.height, visible.height)
      frame.origin.x = visible.midX - frame.size.width / 2
      frame.origin.y = visible.midY - frame.size.height / 2
    } else {
      frame.size = targetSize
    }
    self.setFrame(frame, display: true)
    self.minSize = NSSize(width: 900, height: 600)
    self.title = "Local2API"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
