import Foundation
import AppKit
import SwiftUI
import Testing
import DafeiyuCore
@testable import Dafeiyu

@Suite(.serialized) @MainActor struct AppTests {
    @Test func animationSettingsRenderWhenBothIntervalsAreAtMaximum() throws {
        _ = NSApplication.shared
        let m = try model(); m.preferences.ambientMin = 600; m.preferences.ambientMax = 600; m.preferences.lastPane = "animation"
        let quota = QuotaStore(model: m, disabled: true); defer { quota.stop() }
        let settings = SettingsView(model: m, quota: quota, portrait: nil, requestNotifications: {})
        let host = NSHostingView(rootView: settings.animation)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 690)
        host.layoutSubtreeIfNeeded()
        #expect(m.preferences.ambientMin == 600 && m.preferences.ambientMax == 600)
    }
    @Test func retinaGazeUsesSharedBodyAndAlignedEyeLayers() {
        let assets = AssetStore()
        #expect(assets.gazeLayout.density == 2)
        #expect(assets.gazeFaces.count == 32)
        #expect(assets.texture("look-0")?.usesMipmaps == true)
        #expect(assets.texture("look-1")?.usesMipmaps == false)
        for direction in 0..<32 {
            #expect(assets.texture("look-0", frame: direction)?.size() == CGSize(width: 512, height: 416))
            for stage in 1..<4 {
                #expect(assets.texture("look-\(stage)", frame: direction)?.size() == CGSize(width: 256, height: 160))
            }
        }
        let scene = PetScene(assets: assets)
        scene.look = 29; scene.blink = 3; scene.refresh(now: 0)
        #expect(scene.body.size == CGSize(width: 256, height: 208))
        #expect(scene.body.texture?.size() == CGSize(width: 512, height: 416))
        #expect(!scene.gazeEyes.isHidden)
        #expect(scene.gazeEyes.position == CGPoint(x: 0, y: 120))
        scene.blink = 0; scene.refresh(now: 0); #expect(scene.gazeEyes.isHidden)
        scene.play("waving"); scene.refresh(now: 0); #expect(scene.gazeEyes.isHidden)
        #expect(assets.portrait()?.size == CGSize(width: 192, height: 208))
        #expect(assets.portrait() === assets.portrait())
        let portrait = assets.portrait()?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #expect(portrait?.width == 384 && portrait?.height == 416)
        #expect(assets.clips["jog"]?.frames == 8)   // drawn frames with the arm swing (0.1.22); no in-betweens
        #expect(assets.clips["waving"]?.frames == 32)
    }
    func model() throws -> AppModel {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dafeiyu-regression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel(isolated: true, testDirectory: folder.path)
        model.preferences.refreshMinutes = 0
        model.preferences.codexEnabled = false
        return model
    }
    func sample(_ provider: String = "claude", used: Double = 30) -> QuotaSnapshot {
        try! QuotaParser.parse(Data("{\"provider\":\"\(provider)\",\"primary\":{\"usedPercent\":\(used),\"windowMinutes\":300}}".utf8), provider: provider)
    }
    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(condition(), "Asynchronous store did not settle")
    }
    @Test func preferencesPersistAndReloadWithoutTouchingNormalProfile() throws {
        let m = try model(); m.preferences.speechStyle = .custom; m.preferences.customSpeech["wipeRequest"] = "洗脸时间"; m.preferences.scale = 1.25; m.save()
        let reloaded = AppModel(isolated: true, testDirectory: m.directory.path)
        #expect(reloaded.preferences.scale == 1.25)
        #expect(reloaded.preferences.customSpeech["wipeRequest"] == "洗脸时间")
        #expect(reloaded.directory == m.directory)
    }
    @Test func pageResetPreservesOtherSettingsAndResetAllPreservesLoginFlag() throws {
        let m = try model(); m.preferences.scale = 1.4; m.preferences.speechStyle = .tsundere; m.preferences.performance = .economy
        m.resetPage("speech"); #expect(m.preferences.speechStyle == .soft); #expect(m.preferences.scale == 1.4); #expect(m.preferences.performance == .economy)
        m.preferences.launchAtLogin = true; m.resetAll(); #expect(m.preferences.launchAtLogin); #expect(m.preferences.scale == 1)
        m.preferences.launchAtLogin = false
    }
    @Test func invalidImportPreservesStateAndValidImportKeepsLoginChoice() throws {
        let m = try model(); m.preferences.scale = 1.3; m.preferences.launchAtLogin = true
        let file = m.directory.appendingPathComponent("import.json")
        try Data("[]".utf8).write(to: file); m.importPreferences(from: file); #expect(m.preferences.scale == 1.3); #expect(m.notice != nil)
        try Data("{\"scale\":0.8,\"launchAtLogin\":false}".utf8).write(to: file); m.importPreferences(from: file)
        #expect(m.preferences.scale == 0.8); #expect(m.preferences.launchAtLogin)
        m.preferences.launchAtLogin = false
    }
    @Test func exportContainsPreferencesButNoAccountOrHistory() throws {
        let m = try model(); m.preferences.positionX = 900; m.preferences.launchAtLogin = true
        let file = m.directory.appendingPathComponent("export.json"); m.exportPreferences(to: file)
        let exported = try Preferences.decodeMigrating(Data(contentsOf: file)); #expect(!exported.launchAtLogin); #expect(exported.positionX == nil)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect(json["account"] == nil && json["token"] == nil && json["history"] == nil)
        m.preferences.launchAtLogin = false
    }
    @Test func disabledNetworkNeverInvokesReader() async throws {
        let m = try model(); var calls = 0
        let store = QuotaStore(model: m, disabled: true, readProvider: { id in calls += 1; return sample(id) }); defer { store.stop() }
        store.refresh(); store.refreshIfStale(); try await Task.sleep(nanoseconds: 40_000_000)
        #expect(calls == 0); #expect(!store.isRefreshing)
    }
    @Test func successfulRefreshPersistsThenErrorKeepsLastSnapshot() async throws {
        let m = try model(); var fail = false
        let store = QuotaStore(model: m, disabled: false, readProvider: { id in if fail { throw QuotaFailure.unavailable("fixture offline") }; return sample(id) }); defer { store.stop() }
        store.refresh(); try await waitUntil { !store.isRefreshing }
        #expect(store.providers["claude"]?.snapshot?.windows.first?.remaining == 70)
        #expect(FileManager.default.fileExists(atPath: m.directory.appendingPathComponent("quota-claude.json").path))
        fail = true; store.providers["claude"]?.lastAttempt = .distantPast; store.refresh(); try await waitUntil { !store.isRefreshing }
        #expect(store.providers["claude"]?.snapshot?.windows.first?.remaining == 70); #expect(store.providers["claude"]?.error == "fixture offline")
        #expect(store.providers["claude"]?.loading == false)
    }
    @Test func duplicateRefreshIsCoalescedAndRecentAttemptIsThrottled() async throws {
        let m = try model(); var calls = 0
        let store = QuotaStore(model: m, disabled: false, readProvider: { id in calls += 1; try await Task.sleep(nanoseconds: 40_000_000); return sample(id) }); defer { store.stop() }
        store.refresh(); store.refresh(); try await waitUntil { !store.isRefreshing }; store.refresh()
        #expect(calls == 1); #expect(!store.isRefreshing)
    }
    @Test func disablingProviderDuringRefreshClearsSpinnerAndDiscardsResult() async throws {
        let m = try model()
        let store = QuotaStore(model: m, disabled: false, readProvider: { id in try await Task.sleep(nanoseconds: 70_000_000); return sample(id) }); defer { store.stop() }
        store.refresh(); try await waitUntil { store.providers["claude"]?.loading == true }
        m.preferences.claudeEnabled = false; store.settingsChanged()
        try await waitUntil { !store.isRefreshing }
        #expect(store.providers["claude"]?.loading == false)
        #expect(store.providers["claude"]?.snapshot == nil)
    }
    @Test func stoppingInflightRefreshCannotPersistLateResult() async throws {
        let m = try model()
        let store = QuotaStore(model: m, disabled: false, readProvider: { id in try? await Task.sleep(nanoseconds: 80_000_000); return sample(id) })
        store.refresh(); try await waitUntil { store.providers["claude"]?.loading == true }; store.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(!store.isRefreshing); #expect(store.providers["claude"]?.loading == false); #expect(store.providers["claude"]?.snapshot == nil)
        #expect(!FileManager.default.fileExists(atPath: m.directory.appendingPathComponent("quota-claude.json").path))
    }
}
