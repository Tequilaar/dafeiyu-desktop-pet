import Foundation
import AppKit
import Testing
import DafeiyuCore
@testable import Dafeiyu

// 0.1.16: rice pours in on a quota reset while she clasps her hands; hanging from a window edge.
@Suite(.serialized) @MainActor struct NewActionTests {
    static var windows: [WindowLedge.Window] = []
    func controller(at point: NSPoint? = nil) -> DesktopController {
        _ = NSApplication.shared
        let model = AppModel(isolated: true, testDirectory: NSTemporaryDirectory() + "actions-" + UUID().uuidString)
        model.preferences.wave = false; model.preferences.dailyRhythm = false; model.preferences.aiCompanion = false
        model.preferences.hideInFullscreen = false; model.preferences.respectReduceMotion = false
        model.preferences.ambientMin = 600; model.preferences.ambientMax = 600
        let visible = NSScreen.screens[0].visibleFrame
        model.preferences.positionX = point?.x ?? visible.midX; model.preferences.positionY = point?.y ?? visible.minY + 40
        let d = DesktopController(model: model, assets: AssetStore())
        d.idleSource = { 0 }; d.windowSource = { Self.windows }
        return d
    }
    func close(_ d: DesktopController) { d.stop(); d.panel.close(); d.bowlPanel.close() }
    func frames(_ d: DesktopController, _ count: Int) {
        var t = ProcessInfo.processInfo.systemUptime
        for _ in 0..<count { t += 1.0 / 60; d.scene.onFrame?(t) }
    }
    func snapshot(used: Double) throws -> QuotaSnapshot {
        try QuotaParser.parse(Data("{\"primary\":{\"usedPercent\":\(used),\"windowMinutes\":300}}".utf8), provider: "codex")
    }
    func event(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    /// Drags her body so that her feet end `lift` points above where they started, then lets go.
    func drop(_ d: DesktopController, feetAt y: Double) {
        let start = NSPoint(x: d.characterFrame.midX, y: d.characterFrame.minY + 110)
        let end = NSPoint(x: start.x, y: start.y + y - d.characterFrame.minY)
        d.mouseDown(.body, event: event(.leftMouseDown, start))
        d.mouseDragged(.body, event: event(.leftMouseDragged, end))
        d.mouseUp(.body, event: event(.leftMouseUp, end))
    }

    @Test func quotaResetPoursRiceAndSheClaspsHerHands() async throws {
        Self.windows = []
        let d = controller(); defer { close(d) }
        let store = QuotaStore(model: d.model, disabled: true); defer { store.stop() }
        d.model.preferences.bowlQuotaSource = "codex"; d.observeQuota(store)
        store.providers["codex"] = .init(snapshot: try snapshot(used: 94))
        #expect(!d.isSurprised); #expect(!d.bowlScene.isPouring)
        store.providers["codex"] = .init(snapshot: try snapshot(used: 0))     // new window: 100% left
        #expect(d.isSurprised); #expect(d.bowlScene.isPouring); #expect(d.bowlScene.displayedFraction == 1)
        try await Task.sleep(nanoseconds: 400_000_000); frames(d, 2)
        #expect(d.scene.clip == "surprised"); #expect(!d.scene.useGaze)
        try await Task.sleep(nanoseconds: 2_900_000_000); frames(d, 2)
        #expect(!d.isSurprised); #expect(d.scene.useGaze); #expect(!d.bowlScene.isPouring)
    }
    @Test func smallChangesAndTheSwitchOffDoNotSurpriseHer() throws {
        Self.windows = []
        let d = controller(); defer { close(d) }
        let store = QuotaStore(model: d.model, disabled: true); defer { store.stop() }
        d.model.preferences.bowlQuotaSource = "codex"; d.observeQuota(store)
        store.providers["codex"] = .init(snapshot: try snapshot(used: 50))
        store.providers["codex"] = .init(snapshot: try snapshot(used: 45))   // a 5-point rise is not a reset
        #expect(!d.isSurprised)
        d.model.preferences.resetSurprise = false
        store.providers["codex"] = .init(snapshot: try snapshot(used: 0))
        #expect(!d.isSurprised); #expect(d.bowlScene.isPouring)               // the rice still pours in
    }
    @Test func letGoBelowAWindowTopSheHangsThenDrops() async throws {
        let visible = NSScreen.screens[0].visibleFrame
        let window = CGRect(x: visible.midX - 300, y: visible.minY + 100, width: 600, height: 300)
        Self.windows = [(9, window)]
        let d = controller(); defer { close(d) }
        drop(d, feetAt: window.maxY - 180)
        #expect(d.isHanging); #expect(d.scene.clip == "hanging")
        #expect(abs(d.characterFrame.minY + 197 - window.maxY) < 1)     // hands on the window edge
        try await Task.sleep(nanoseconds: 300_000_000); frames(d, 1)
        #expect((d.scene.frameOverride ?? -1) < 8)                        // the big swing first…
        try await Task.sleep(nanoseconds: 2_300_000_000); frames(d, 1)
        #expect((d.scene.frameOverride ?? -1) >= 8)                       // …then the gentle one
        try await Task.sleep(nanoseconds: 2_100_000_000); frames(d, 2)
        #expect(!d.isHanging)
        frames(d, 120)
        #expect(abs(d.characterFrame.minY - (visible.minY + 4)) < 1)    // fell to the floor
    }
    @Test func hangingWindowClosesAndSheFalls() async throws {
        let visible = NSScreen.screens[0].visibleFrame
        let window = CGRect(x: visible.midX - 300, y: visible.minY + 100, width: 600, height: 300)
        Self.windows = [(4, window)]
        let d = controller(); defer { close(d) }
        drop(d, feetAt: window.maxY - 200)
        #expect(d.isHanging)
        Self.windows = []
        try await Task.sleep(nanoseconds: 600_000_000); frames(d, 2)
        #expect(!d.isHanging); #expect(d.model.status == "手酸了，松手")
    }
    @Test func hangingNeedsTheEdgeOverheadAndTheSwitchOn() throws {
        let visible = NSScreen.screens[0].visibleFrame
        let window = CGRect(x: visible.midX - 300, y: visible.minY + 100, width: 600, height: 300)
        Self.windows = [(5, window)]
        let d = controller(); defer { close(d) }
        drop(d, feetAt: window.maxY - 60)            // edge at her knees: no grip
        #expect(!d.isHanging)
        d.model.preferences.hangOnWindows = false
        drop(d, feetAt: window.maxY - 180)
        #expect(!d.isHanging)
    }
    @Test func standingOnAWindowSheSitsAndSwingsHerLegs() async throws {
        let visible = NSScreen.screens[0].visibleFrame
        let window = CGRect(x: visible.midX - 300, y: visible.minY + 200, width: 600, height: 200)
        Self.windows = [(6, window)]
        let d = controller(at: NSPoint(x: visible.midX, y: window.maxY + 10)); defer { close(d) }
        d.sitAfter = 0.3
        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(d.isSitting); #expect(d.scene.clip == "sitting")
        #expect(abs(d.characterFrame.minY + 58 - window.maxY) < 1)       // legs hang over the edge
        Self.windows = []                                                 // the window goes away
        try await Task.sleep(nanoseconds: 700_000_000); frames(d, 2)
        #expect(!d.isSitting); #expect(d.model.status == "窗户跑掉啦")
    }
    @Test func dozingSheLiesDownAndKneelsBeforeStandingUp() async throws {
        Self.windows = []
        let d = controller(); defer { close(d) }
        d.idleSource = { 400 }
        try await Task.sleep(nanoseconds: 1_600_000_000); frames(d, 2)
        #expect(d.isLyingDown); #expect(d.scene.clip == "sleeping")
        d.idleSource = { 0 }
        try await Task.sleep(nanoseconds: 1_200_000_000); frames(d, 2)
        #expect(!d.isLyingDown); #expect(d.scene.useGaze); #expect(d.model.status == "在这里陪你")
    }
    @Test func everyAtlasHoldsExactlyItsDeclaredGrid() throws {
        // A sheet packed in one row but declared as 8 columns would show the wrong frames.
        let assets = AssetStore()
        for (name, clip) in assets.clips where !name.hasPrefix("look-") {
            let image = try #require(NSImage(contentsOf: assets.root.appendingPathComponent(name + ".png"))?.representations.first)
            let rows = (clip.frames + clip.columns - 1) / clip.columns
            #expect(image.pixelsWide == clip.columns * clip.width, "\(name)")
            #expect(image.pixelsHigh == rows * clip.height, "\(name)")
        }
    }
    @Test func wanderingSheWalksOverAndLooksAtAWindow() async throws {
        let visible = NSScreen.screens[0].visibleFrame
        let window = CGRect(x: visible.minX + 150, y: visible.midY, width: 400, height: 200)   // floats: no climbing
        Self.windows = [(11, window)]
        let d = controller(at: NSPoint(x: visible.maxX - 300, y: visible.minY + 4)); defer { close(d) }
        d.random = { 0.5 }; d.iconSource = { [] }
        d.startWander()
        #expect(d.isWandering); #expect(d.model.status == "出去走走")
        let start = d.characterFrame.midX
        frames(d, 30); #expect(d.characterFrame.midX < start - 10); #expect(d.scene.clip == "walking-left")
        frames(d, 60 * 20)                                                    // arrive beside the window
        #expect(abs(d.characterFrame.midX - (window.maxX - 60)) < 1); #expect(d.scene.useGaze)
        try await Task.sleep(nanoseconds: 3_700_000_000); frames(d, 2)
        #expect(!d.isWandering)
    }
    @Test func wanderingSheClimbsAWindowThatReachesTheFloor() throws {
        let visible = NSScreen.screens[0].visibleFrame
        let window = CGRect(x: visible.midX, y: visible.minY, width: 500, height: 300)
        Self.windows = [(12, window)]
        let d = controller(at: NSPoint(x: visible.midX - 300, y: visible.minY + 4)); defer { close(d) }
        d.random = { 0.1 }; d.iconSource = { [] }
        d.startWander()
        frames(d, 60 * 10)                                                    // walk to the wall
        #expect(d.scene.clip == "climbing-right")
        frames(d, 60 * 12)                                                    // climb up and pull up
        #expect(!d.isWandering); #expect(abs(d.characterFrame.minY - window.maxY) < 1)
        #expect(abs(d.characterFrame.midX - (window.minX + 40)) < 1)
    }
    @Test func wanderingLooksUpAtADockIconAndCanBeSwitchedOff() throws {
        let visible = NSScreen.screens[0].visibleFrame
        Self.windows = []
        let d = controller(at: NSPoint(x: visible.midX, y: visible.minY + 4)); defer { close(d) }
        d.random = { 0.1 }; d.iconSource = { [("Safari", CGRect(x: visible.maxX - 20, y: visible.midY, width: 50, height: 50))] }
        d.startWander()
        frames(d, 60 * 30)
        #expect(d.scene.useGaze); #expect(d.model.status == "出去走走")
        #expect(d.characterFrame.midX > visible.maxX - 120)                   // walked to the right end under the Dock
        d.model.preferences.wanderLevel = 0
        #expect(d.model.preferences.wanderLevel == 0)
    }
}
