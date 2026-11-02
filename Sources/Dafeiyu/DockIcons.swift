import AppKit
import ApplicationServices

/// Positions and names of the Dock's items, read through Accessibility. Works only after the
/// user has granted 大肥鱼 Accessibility access; nothing else is read (no window titles or content).
@MainActor enum DockIcons {
    static var trusted: Bool { AXIsProcessTrusted() }
    /// Shows macOS's own permission prompt. Called only from the user's click in Settings.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    /// Opens System Settings at Privacy & Security → Accessibility. macOS shows no prompt when an
    /// older entry for 大肥鱼 is already listed, so the user removes it there and adds the app again.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    private static var cache: (time: Double, items: [(name: String, frame: CGRect)])?
    /// Item frames in Cocoa coordinates; cached for 30 s.
    static func read(now: Double) -> [(name: String, frame: CGRect)] {
        if let cache, now - cache.time < 30 { return cache.items }
        var items: [(name: String, frame: CGRect)] = []
        if trusted, let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            let app = AXUIElementCreateApplication(dock.processIdentifier)
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            for list in children(app) where string(list, kAXRoleAttribute) == kAXListRole {
                for item in children(list) {
                    guard let name = string(item, kAXTitleAttribute), !name.isEmpty,
                          let origin = point(item), let size = size(item), size.width > 8 else { continue }
                    items.append((name, CGRect(x: origin.x, y: primaryTop - origin.y - size.height, width: size.width, height: size.height)))
                }
            }
        }
        cache = (now, items); return items
    }
    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
    private static func point(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?; var point = CGPoint.zero
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }
    private static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?; var size = CGSize.zero
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
