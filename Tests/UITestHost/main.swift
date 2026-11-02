import AppKit
final class TestArea: NSView {
    let label = NSTextField(labelWithString: "弹窗关闭测试 · 点击这里的空白区域")
    var clicks = 0
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        label.frame = NSRect(x: 30, y: 170, width: 440, height: 28); label.alignment = .center; addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {
        clicks += 1; label.stringValue = "已接收空白处点击：\(clicks) 次"
        let probe: [String: Any] = ["clicks": clicks, "active": NSApp.isActive,
            "frontmostIsThisApp": NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
            "pressedButtons": NSEvent.pressedMouseButtons, "keyWindow": window?.isKeyWindow == true]
        if let data = try? JSONSerialization.data(withJSONObject: probe, options: .sortedKeys) {
            try? data.write(to: URL(fileURLWithPath: "/private/tmp/dafeiyu-ui-external-event.json"))
        }
    }
}
let app = NSApplication.shared; app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 60, y: 200, width: 500, height: 360), styleMask: [.titled,.closable], backing: .buffered, defer: false)
window.title = "大肥鱼 · 自有空白测试窗口"; window.contentView = TestArea(frame: NSRect(x:0,y:0,width:500,height:360))
window.makeKeyAndOrderFront(nil)
DispatchQueue.main.asyncAfter(deadline: .now()+240) { app.terminate(nil) }
app.run()
