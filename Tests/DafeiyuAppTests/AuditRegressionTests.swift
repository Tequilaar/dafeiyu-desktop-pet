import Foundation
import AppKit
import Testing
import DafeiyuCore
@testable import Dafeiyu

// Regressions found by the 2026-10-29 full audit (0.1.12).
@Suite(.serialized) @MainActor struct AuditRegressionTests {
    func controller(display: UInt32, at point: NSPoint) -> DesktopController {
        _ = NSApplication.shared
        let model = AppModel(isolated: true, testDirectory: NSTemporaryDirectory() + "audit-test-" + UUID().uuidString)
        model.preferences.bowlQuotaSource = "codex"; model.preferences.wave = false
        model.preferences.hideInFullscreen = false; model.preferences.respectReduceMotion = false
        model.preferences.ambientMin = 600; model.preferences.ambientMax = 600
        model.preferences.displayID = display; model.preferences.positionX = point.x; model.preferences.positionY = point.y
        return DesktopController(model: model, assets: AssetStore())
    }
    func close(_ d: DesktopController) { d.stop(); d.panel.close(); d.bowlPanel.close() }
    func id(_ screen: NSScreen) -> UInt32 { screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0 }
    func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// "主显示器" is the primary display, not NSScreen.main (which follows keyboard focus).
    @Test func automaticDisplayKeepsPetAndBowlTogetherOnEachScreen() throws {
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            let d = controller(display: screen == NSScreen.screens[0] ? 0 : id(screen), at: NSPoint(x: visible.midX, y: visible.minY + 30))
            defer { close(d) }
            let home = NSScreen.screens[0] == screen ? NSScreen.screens[0].visibleFrame : visible
            #expect(home.contains(NSPoint(x: d.characterFrame.midX, y: d.characterFrame.minY + 1)))
            #expect(home.contains(NSPoint(x: d.bowlPanel.frame.midX, y: d.bowlPanel.frame.midY)))
            #expect(abs(d.bowlPanel.frame.midX - d.characterFrame.midX) < 120)
            #expect(abs(d.bowlPanel.frame.midY - d.characterFrame.minY) < 140)
        }
    }
    @Test func savedPositionOnAnotherDisplayIsBroughtToThePrimaryOne() throws {
        guard let other = NSScreen.screens.dropFirst().first else { return }
        let d = controller(display: 0, at: NSPoint(x: other.visibleFrame.midX, y: other.visibleFrame.midY)); defer { close(d) }
        #expect(NSScreen.screens[0].frame.contains(NSPoint(x: d.characterFrame.midX, y: d.characterFrame.minY + 1)))
        #expect(NSScreen.screens[0].frame.contains(NSPoint(x: d.bowlPanel.frame.midX, y: d.bowlPanel.frame.midY)))
    }
    @Test func topEdgeLetsHerHeadReachTheMenuBar() throws {
        let visible = NSScreen.screens[0].visibleFrame
        let d = controller(display: 0, at: NSPoint(x: visible.midX, y: visible.maxY + 500)); defer { close(d) }
        #expect(abs(d.characterFrame.minY + 196 - visible.maxY) < 1)          // head just under the menu bar
        #expect(abs(d.bowlPanel.frame.midY - (d.characterFrame.minY + 30)) < 1)
        // AppKit may not push the window back down on its own.
        #expect(d.panel.constrainFrameRect(d.panel.frame, to: NSScreen.screens[0]) == d.panel.frame)
        #expect(abs(d.scene.bubbleCeiling - 196) < 1)                          // the bubble moves down to stay readable
    }
    @Test func sleepHidesWindowsAndWakeBringsThemBack() throws {
        let visible = NSScreen.screens[0].visibleFrame
        let d = controller(display: 0, at: NSPoint(x: visible.midX, y: visible.minY + 200)); defer { close(d) }
        #expect(d.panel.isVisible)
        d.systemWillSleep()   // a real broadcast would also put controllers of parallel suites to sleep
        #expect(!d.panel.isVisible); #expect(!d.bowlPanel.isVisible); #expect(d.petView.renderingPaused)
        d.systemDidWake()
        #expect(d.panel.isVisible); #expect(d.bowlPanel.isVisible); #expect(!d.petView.renderingPaused)
    }
    @Test func dragGestureWithMovingDisabledDoesNotOpenTheCard() throws {
        let d = controller(display: 0, at: NSPoint(x: NSScreen.screens[0].visibleFrame.midX, y: NSScreen.screens[0].visibleFrame.minY + 200))
        defer { close(d) }
        var cards = 0; d.showQuota = { cards += 1 }
        d.model.preferences.draggable = false; d.model.preferences.touch = false
        let p = NSPoint(x: d.characterFrame.midX, y: d.characterFrame.minY + 140), before = d.characterFrame
        d.mouseDown(.body, event: event(.leftMouseDown, p))
        d.mouseDragged(.body, event: event(.leftMouseDragged, NSPoint(x: p.x + 60, y: p.y)))
        d.mouseUp(.body, event: event(.leftMouseUp, NSPoint(x: p.x + 60, y: p.y)))
        #expect(cards == 0); #expect(d.characterFrame == before)
        d.mouseDown(.body, event: event(.leftMouseDown, p)); d.mouseUp(.body, event: event(.leftMouseUp, p))
        #expect(cards == 1)
    }
    /// A lapsed Claude login doubled the shared backoff and left the Codex bowl stale for 20–40 minutes.
    @Test func failingProviderBacksOffWithoutDelayingTheOther() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("audit-quota-" + UUID().uuidString)
        let m = AppModel(isolated: true, testDirectory: folder.path); m.preferences.refreshMinutes = 5
        var reads: [String] = []
        let store = QuotaStore(model: m, disabled: false, readProvider: { id in
            reads.append(id)
            if id == "claude" { throw QuotaFailure.unavailable("expired fixture") }
            return try QuotaParser.parse(Data("{\"primary\":{\"usedPercent\":40,\"windowMinutes\":10080}}".utf8), provider: id)
        }); defer { store.stop() }
        func settle() async throws { for _ in 0..<150 where store.isRefreshing { try await Task.sleep(nanoseconds: 10_000_000) } }
        store.refresh(); try await settle()
        #expect(Set(reads) == ["claude", "codex"]); reads.removeAll()
        // Five minutes later only Codex is due; Claude waits ten after one failure.
        store.providers["claude"]?.lastAttempt = Date().addingTimeInterval(-301)
        store.providers["codex"]?.lastAttempt = Date().addingTimeInterval(-301)
        store.refresh(scheduled: true); try await settle()
        #expect(reads == ["codex"]); reads.removeAll()
        store.providers["claude"]?.lastAttempt = Date().addingTimeInterval(-601)
        store.providers["codex"]?.lastAttempt = Date().addingTimeInterval(-601)
        store.refresh(scheduled: true); try await settle()
        #expect(Set(reads) == ["claude", "codex"])
        #expect(store.providers["codex"]?.error == nil); #expect(store.providers["claude"]?.error == "expired fixture")
    }
}

// 0.1.15: launched while the session was locked, the SKView never started rendering (gray box).
@Suite(.serialized) @MainActor struct RendererRecoveryTests {
    @Test func recoveringRendererKeepsScenesAndWindowsAndDrawingResumes() async throws {
        _ = NSApplication.shared
        let model = AppModel(isolated: true, testDirectory: NSTemporaryDirectory() + "renderer-" + UUID().uuidString)
        model.preferences.bowlQuotaSource = "off"; model.preferences.wave = false; model.preferences.hideInFullscreen = false
        model.preferences.ambientMin = 600; model.preferences.ambientMax = 600
        let d = DesktopController(model: model, assets: AssetStore()); defer { d.stop(); d.panel.close(); d.bowlPanel.close() }
        let frame = d.panel.frame
        d.recoverRenderer()
        #expect(d.panel.contentView === d.petView); #expect(d.bowlPanel.contentView === d.bowlView)
        #expect(d.petView.scene === d.scene); #expect(d.bowlView.scene === d.bowlScene)
        #expect(d.panel.frame == frame); #expect(d.rendererKicks == 1); #expect(!d.petView.isPaused)
        let before = d.frameCount
        for _ in 0..<40 where d.frameCount == before { try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(d.frameCount > before)
    }
}
