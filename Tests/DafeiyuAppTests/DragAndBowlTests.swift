import Foundation
import AppKit
import CryptoKit
import SpriteKit
import Testing
import DafeiyuCore
@testable import Dafeiyu

@Suite(.serialized) @MainActor struct DragAndBowlTests {
    func controller() throws -> DesktopController {
        _ = NSApplication.shared
        let model = AppModel(isolated: true, testDirectory: NSTemporaryDirectory() + "drag-test-" + UUID().uuidString)
        model.preferences.bowlQuotaSource = "off"; model.preferences.wave = false
        model.preferences.hideInFullscreen = false; model.preferences.respectReduceMotion = false
        model.preferences.ambientMin = 600; model.preferences.ambientMax = 600
        model.preferences.displayID = (NSScreen.screens[0].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
        model.preferences.positionX = NSScreen.screens[0].visibleFrame.midX
        model.preferences.positionY = NSScreen.screens[0].visibleFrame.minY + 200
        return DesktopController(model: model, assets: AssetStore())
    }
    func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                          windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    func close(_ d: DesktopController) { d.stop(); d.panel.close(); d.bowlPanel.close() }
    @Test func draggingBodyStartsOriginalRunReversesAndStopsOnRelease() throws {
        let d = try controller(); defer { close(d) }
        let p = NSPoint(x: d.characterFrame.midX, y: d.characterFrame.minY + 140)
        d.mouseDown(.body, event: event(.leftMouseDown, p))
        d.mouseDragged(.body, event: event(.leftMouseDragged, NSPoint(x: p.x + 2, y: p.y)))
        #expect(d.scene.useGaze)
        d.mouseDragged(.body, event: event(.leftMouseDragged, NSPoint(x: p.x + 70, y: p.y)))
        #expect(!d.scene.useGaze); #expect(d.scene.clip == "running-right")
        d.scene.refresh(now: ProcessInfo.processInfo.systemUptime)
        #expect(d.scene.body.texture?.size() == CGSize(width: 384, height: 416))
        d.mouseDragged(.body, event: event(.leftMouseDragged, NSPoint(x: p.x - 50, y: p.y)))
        #expect(d.scene.clip == "running-left")
        d.mouseUp(.body, event: event(.leftMouseUp, NSPoint(x: p.x - 50, y: p.y)))
        #expect(d.scene.useGaze); #expect(d.scene.frameOverride == nil)
        let edgePress = NSPoint(x: d.characterFrame.midX, y: d.characterFrame.minY + 140)
        let edge = NSPoint(x: 100_000, y: -100_000)
        d.mouseDown(.body, event: event(.leftMouseDown, edgePress))
        d.mouseDragged(.body, event: event(.leftMouseDragged, edge))
        d.mouseUp(.body, event: event(.leftMouseUp, edge))
        let screen = NSScreen.screens[0].visibleFrame
        #expect(d.bowlPanel.frame.midX + 58 <= screen.maxX)
        #expect(d.bowlPanel.frame.midY - 44 >= screen.minY)
        let data = try Data(contentsOf: d.assets.root.appendingPathComponent("jog.png"))
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == "4fbd59440a8107cca4e6b440b006dbe3bd9066a9c4c8067a6733ba972dd871c6")
    }
    @Test func holdingStillStopsRunAndSwitchCanDisableIt() async throws {
        let d = try controller(); defer { close(d) }
        let p = NSPoint(x: d.characterFrame.midX, y: d.characterFrame.minY + 140)
        d.mouseDown(.body, event: event(.leftMouseDown, p))
        d.mouseDragged(.body, event: event(.leftMouseDragged, NSPoint(x: p.x + 60, y: p.y)))
        #expect(!d.scene.useGaze)
        try await Task.sleep(nanoseconds: 200_000_000)
        d.scene.onFrame?(ProcessInfo.processInfo.systemUptime)
        #expect(d.scene.useGaze)
        d.model.preferences.runWhileDragging = false
        d.mouseDragged(.body, event: event(.leftMouseDragged, NSPoint(x: p.x - 60, y: p.y)))
        #expect(d.scene.useGaze); #expect(d.characterFrame.midX < p.x)
        d.mouseUp(.body, event: event(.leftMouseUp, NSPoint(x: p.x - 60, y: p.y)))
    }
    @Test func wipingFaceIsNotTurnedIntoDraggingRun() throws {
        let d = try controller(); defer { close(d) }
        d.scene.look = 0; d.scene.sootLevel = 1; d.scene.refresh(now: ProcessInfo.processInfo.systemUptime)
        let p = NSPoint(x: d.characterFrame.midX, y: d.characterFrame.minY + 108), before = d.characterFrame
        d.mouseDown(.body, event: event(.leftMouseDown, p))
        d.mouseDragged(.body, event: event(.leftMouseDragged, NSPoint(x: p.x + 20, y: p.y)))
        #expect(d.characterFrame == before); #expect(d.scene.useGaze); #expect(d.scene.sootLevel < 1)
        d.mouseUp(.body, event: event(.leftMouseUp, NSPoint(x: p.x + 20, y: p.y)))
    }
    @Test func bowlReturnsToLatestQuotaAfterStoryOverride() throws {
        let bowl = BowlScene(assets: AssetStore()), p = Preferences()
        func reading(_ used: Double) throws -> BowlQuotaReading? {
            let snapshot = try QuotaParser.parse(Data("{\"primary\":{\"usedPercent\":\(used),\"windowMinutes\":300}}".utf8), provider: "codex")
            return BowlQuotaReading.make(preferences: p, snapshot: snapshot)
        }
        bowl.setQuota(try reading(25), showLabel: true)
        #expect(bowl.displayedFraction == 0.75); #expect(bowl.quotaIsDisplayed)
        bowl.setRice(false); #expect(!bowl.quotaIsDisplayed)
        bowl.setQuota(try reading(90), showLabel: true); #expect(!bowl.quotaIsDisplayed)
        bowl.resumeQuota(); #expect(bowl.displayedFraction == 0.1); #expect(bowl.quotaIsDisplayed)
        bowl.setQuota(nil, showLabel: true); #expect(!bowl.quotaIsDisplayed)
    }
    @Test func bowlLevelsRenderUsingExistingRiceArtwork() throws {
        let scene = BowlScene(assets: AssetStore()), view = SKView(frame: CGRect(x: 0, y: 0, width: 256, height: 256))
        view.presentScene(scene)
        let folder = ProcessInfo.processInfo.environment["DAFEIYU_BOWL_PREVIEW_DIR"].map { URL(fileURLWithPath: $0) }
        if let folder { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for remaining in [100, 75, 50, 25, 1, 0] {
            let snapshot = try QuotaParser.parse(Data("{\"primary\":{\"usedPercent\":\(100 - remaining),\"windowMinutes\":300}}".utf8), provider: "codex")
            scene.setQuota(BowlQuotaReading.make(preferences: Preferences(), snapshot: snapshot), showLabel: true)
            let texture = try #require(view.texture(from: scene, crop: CGRect(x: 0, y: 0, width: 128, height: 128)))
            #expect(scene.bowl.calculateAccumulatedFrame().minY >= 0)
            #expect(scene.bowl.calculateAccumulatedFrame().maxX <= 128)
            if let folder {
                let image = NSBitmapImageRep(cgImage: texture.cgImage())
                try #require(image.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("rice-\(remaining).png"))
            }
        }
    }
}
