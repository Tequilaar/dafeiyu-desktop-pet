import Foundation
import AppKit
import Testing
import DafeiyuCore
@testable import Dafeiyu

// 0.1.14: dozing while away, standing on windows and falling off, feeding.
@Suite(.serialized) @MainActor struct CompanionAppTests {
    func controller(at point: NSPoint? = nil, windows: [WindowLedge.Window] = []) -> DesktopController {
        _ = NSApplication.shared
        let model = AppModel(isolated: true, testDirectory: NSTemporaryDirectory() + "companion-" + UUID().uuidString)
        model.preferences.bowlQuotaSource = "off"; model.preferences.wave = false; model.preferences.dailyRhythm = false
        model.preferences.hideInFullscreen = false; model.preferences.respectReduceMotion = false; model.preferences.aiCompanion = false
        model.preferences.ambientMin = 600; model.preferences.ambientMax = 600
        let visible = NSScreen.screens[0].visibleFrame
        model.preferences.positionX = point?.x ?? visible.midX; model.preferences.positionY = point?.y ?? visible.minY + 200
        Self.windows = windows
        let d = DesktopController(model: model, assets: AssetStore())
        d.idleSource = { 0 }; d.windowSource = { Self.windows }
        return d
    }
    // Window list seen by the controller under test; mutable so a test can "move" a window.
    static var windows: [WindowLedge.Window] = []
    func close(_ d: DesktopController) { d.stop(); d.panel.close(); d.bowlPanel.close() }
    func frames(_ d: DesktopController, _ count: Int) {
        var t = ProcessInfo.processInfo.systemUptime
        for _ in 0..<count { t += 1.0 / 60; d.scene.onFrame?(t) }
    }
    func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<40 where !condition() { try await Task.sleep(nanoseconds: 50_000_000) }
    }

    @Test func dozesWhileTheUserIsAwayAndWakesOnInput() async throws {
        let d = controller(); defer { close(d) }
        d.idleSource = { 400 }        // default: doze after five idle minutes
        try await waitFor { d.model.status == "打了个小盹" }
        #expect(d.model.status == "打了个小盹"); #expect(d.scene.faceReaction == 3)
        d.idleSource = { 0 }
        try await waitFor { d.model.status != "打了个小盹" }
        #expect(d.model.status == "在这里陪你"); #expect(d.scene.faceReaction == 0)
    }
    @Test func napSwitchOffKeepsHerAwake() async throws {
        let d = controller(); defer { close(d) }
        d.model.preferences.napMinutes = 0; d.idleSource = { 4000 }
        try await Task.sleep(nanoseconds: 1_300_000_000)
        #expect(d.model.status != "打了个小盹")
    }
    @Test func standsOnAWindowAndFallsOntoTheNextOneWhenItMoves() async throws {
        let visible = NSScreen.screens[0].visibleFrame
        let upper = CGRect(x: visible.midX - 300, y: visible.minY + 300, width: 600, height: 200)
        let lower = CGRect(x: visible.midX - 400, y: visible.minY + 40, width: 800, height: 120)
        let d = controller(at: NSPoint(x: visible.midX, y: upper.maxY + 10), windows: [(1, upper), (2, lower)]); defer { close(d) }
        try await waitFor { abs(d.characterFrame.minY - upper.maxY) < 1 }
        #expect(abs(d.characterFrame.minY - upper.maxY) < 1)          // snapped onto the window top at launch
        Self.windows = [(1, upper.offsetBy(dx: 0, dy: -500)), (2, lower)]   // the upper window is dragged away
        try await waitFor { d.model.status == "窗户跑掉啦" }
        #expect(d.model.status == "窗户跑掉啦")
        frames(d, 120)
        #expect(abs(d.characterFrame.minY - lower.maxY) < 1)          // caught by the lower window
    }
    @Test func fallsToTheFloorWhenItsWindowCloses() async throws {
        let visible = NSScreen.screens[0].visibleFrame
        let window = CGRect(x: visible.midX - 300, y: visible.minY + 260, width: 600, height: 200)
        let d = controller(at: NSPoint(x: visible.midX, y: window.maxY + 10), windows: [(7, window)]); defer { close(d) }
        try await waitFor { abs(d.characterFrame.minY - window.maxY) < 1 }
        Self.windows = []
        try await waitFor { d.model.status == "窗户跑掉啦" }
        frames(d, 120)
        #expect(abs(d.characterFrame.minY - (visible.minY + 4)) < 1)
    }
    @Test func droppedNearAWindowTopSheStandsOnIt() throws {
        let visible = NSScreen.screens[0].visibleFrame
        let window = CGRect(x: visible.midX - 300, y: visible.minY + 300, width: 600, height: 200)
        let d = controller(windows: [(3, window)]); defer { close(d) }
        let start = NSPoint(x: d.characterFrame.midX, y: d.characterFrame.minY + 140)
        let lift = window.maxY + 14 - d.characterFrame.minY
        func event(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        d.mouseDown(.body, event: event(.leftMouseDown, start))
        d.mouseDragged(.body, event: event(.leftMouseDragged, NSPoint(x: start.x, y: start.y + lift)))
        d.mouseUp(.body, event: event(.leftMouseUp, NSPoint(x: start.x, y: start.y + lift)))
        #expect(abs(d.characterFrame.minY - window.maxY) < 1)
    }
    @Test func feedingPlaysTheEatingClipAndMentionsTheFood() throws {
        let d = controller(); defer { close(d) }
        d.feed(.text("今天的午饭是咖喱饭"))
        #expect(d.model.status == "谢谢投喂"); #expect(d.scene.clip == "steel-eating")
        d.model.preferences.feeding = false
        #expect(!d.canFeed())
    }
}
