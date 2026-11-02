import AppKit
import SwiftUI
import UserNotifications
import Carbon
import DafeiyuCore
import Combine

@main struct DafeiyuApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = ApplicationDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var quota: QuotaStore!
    private var assets: AssetStore!
    private var desktop: DesktopController!
    private var settingsWindow: NSWindow?
    private var popover: NSPopover?
    private var popoverGlobalMonitor: Any?
    private var popoverLocalMonitor: Any?
    private var popoverActivationObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem!
    private var hotkeys: Hotkeys?
    private var metrics: MetricsRecorder?
    private var memorySource: DispatchSourceMemoryPressure?
    private var subscriptions = Set<AnyCancellable>()
    private var statusTimer: Timer?
    private let arguments = CommandLine.arguments
    func applicationDidFinishLaunching(_ notification: Notification) {
        let isolated = arguments.contains("--smoke-test") || arguments.contains("--exercise")
        model = AppModel(isolated: isolated, testDirectory: value(after: "--data-dir")); assets = AssetStore()
        quota = QuotaStore(model: model, disabled: arguments.contains("--no-network"))
        desktop = DesktopController(model: model, assets: assets)
        desktop.observeQuota(quota)
        desktop.showSettings = { [weak self] in self?.openSettings() }
        desktop.showQuota = { [weak self] in self?.toggleQuota() }
        quota.onReset = { [weak self] in self?.desktop.celebrate() }
        quota.notify = { [weak self] title, body in self?.sendNotification(title: title, body: body) }
        let originalPreferencesHandler = model.onPreferences
        model.onPreferences = { [weak self] in
            originalPreferencesHandler?(); self?.quota.settingsChanged(); self?.applyAppearance(); self?.hotkeys?.register()
        }
        makeMenus(); applyAppearance()
        quota.$providers.sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusQuota() } }.store(in: &subscriptions)
        model.$preferences.sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusQuota() } }.store(in: &subscriptions)
        // The "·旧" mark depends on elapsed time, so re-evaluate once a minute.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatusQuota() } }
        statusTimer?.tolerance = 10
        hotkeys = Hotkeys(model: model, jump: { [weak self] in self?.desktop.jumpToPointer() })
        memorySource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        memorySource?.setEventHandler { [weak self] in
            guard let self else { return }; assets.purgeAll(except: [desktop.scene.activeAtlas])
        }
        memorySource?.resume()
        if let folder = value(after: "--diagnostics-dir") { metrics = MetricsRecorder(folder: URL(fileURLWithPath: folder), model: model, assets: assets, desktop: desktop, quotaShown: { [weak self] in self?.popover?.isShown == true }) }
        if arguments.contains("--settings") { openSettings() }
        if arguments.contains("--quota") { toggleQuota() }
        if arguments.contains("--exercise") { exercise() }
        if isolated, arguments.contains("--drag-preview") {
            let folder = value(after: "--diagnostics-dir").map { URL(fileURLWithPath: $0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.desktop.exerciseBodyDrag(log: folder) }
        }
        if isolated, arguments.contains("--bowl-play-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.desktop.exerciseBowlPlay() }
        }
        if isolated, arguments.contains("--refill-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.desktop.exerciseRefill() }
        }
        if isolated, arguments.contains("--climb-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.desktop.exerciseWander(climb: true) }
        }
        if isolated, arguments.contains("--wander-preview") {
            for delay in [3.0, 12, 21] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.desktop.exerciseWander() } }
        }
        if isolated, arguments.contains("--sit-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.desktop.exerciseSit() }
        }
        if isolated, arguments.contains("--doze-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.desktop.exerciseDoze() }
        }
        if isolated, arguments.contains("--hang-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.desktop.exerciseHang() }
        }
        if arguments.contains("--gaze-preview") { desktop.exerciseGaze(seconds: 24, soot: arguments.contains("--soot-preview")) }
        if arguments.contains("--gaze-upper-left-preview") { desktop.exerciseGaze(seconds: 40, soot: arguments.contains("--soot-preview"), upperLeftOnly: true) }
        if let seconds = value(after: "--quit-after").flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
        }
        if !arguments.contains("--no-network") { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.quota.refresh() } }
    }
    private func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }; return arguments[index + 1]
    }
    private func makeMenus() {
        let main = NSMenu(); let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu(); appItem.submenu = app
        let settings = NSMenuItem(title: "设置…", action: #selector(settingsAction), keyEquivalent: ","); settings.target = self; app.addItem(settings)
        let usage = NSMenuItem(title: "查看额度", action: #selector(quotaAction), keyEquivalent: "u")
        usage.target = self; usage.keyEquivalentModifierMask = [.command, .shift]; app.addItem(usage)
        app.addItem(.separator()); app.addItem(withTitle: "退出大肥鱼", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "fish", accessibilityDescription: "大肥鱼")
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("查看额度") { [weak self] in self?.toggleQuota() })
        menu.addItem(ActionMenuItem("设置…") { [weak self] in self?.openSettings() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("显示／隐藏大肥鱼") { [weak self] in self?.model.hidden.toggle() })
        menu.addItem(ActionMenuItem("安静／自然陪伴") { [weak self] in self?.model.quiet.toggle() })
        menu.addItem(ActionMenuItem("暂停／继续互动") { [weak self] in self?.model.paused.toggle() })
        menu.addItem(ActionMenuItem("移回屏幕角落") { [weak self] in self?.desktop.resetPosition() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("退出大肥鱼") { NSApp.terminate(nil) })
        statusItem.menu = menu
    }
    @objc private func quotaAction() { toggleQuota() }
    /// Remaining quota next to the menu-bar fish, from the same source and window as the bowl.
    private func updateStatusQuota() {
        guard let button = statusItem?.button else { return }
        let p = model.preferences, state = quota.providers[p.bowlQuotaSource]
        let reading = p.menuBarQuota ? BowlQuotaReading.make(preferences: p, snapshot: state?.snapshot, loading: state?.loading == true, failed: state?.error != nil) : nil
        guard let reading else {
            button.title = ""; button.toolTip = "大肥鱼"; statusItem.length = NSStatusItem.squareLength; return
        }
        let low = (reading.fraction ?? 1) * 100 < p.lowQuotaThreshold
        let color: NSColor = low ? .systemOrange : reading.stale || reading.fraction == nil ? .secondaryLabelColor : .labelColor
        button.attributedTitle = NSAttributedString(string: " " + reading.compact, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: color])
        button.imagePosition = .imageLeading; button.toolTip = reading.detail
        statusItem.length = NSStatusItem.variableLength
    }
    @objc private func settingsAction() { openSettings() }
    private func applyAppearance() {
        NSApp.appearance = model.preferences.appearance == "dark" ? NSAppearance(named: .darkAqua) : model.preferences.appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
    func openSettings() {
        popover?.performClose(nil)
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = SettingsView(model: model, quota: quota, portrait: assets.portrait(), requestNotifications: requestNotifications)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 690), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "大肥鱼设置"; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 740, height: 620); window.delegate = self
        window.contentView = NSHostingView(rootView: view); window.center(); settingsWindow = window
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func toggleQuota() {
        if popover?.isShown == true { popover?.performClose(nil); return }
        desktop.panel.orderFrontRegardless()
        let popover = NSPopover(); popover.behavior = .transient; popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion; popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: QuotaCard(model: model, quota: quota, portrait: assets.portrait(), openSettings: { [weak self] in self?.openSettings() }))
        self.popover = popover; desktop.cardOpen = true
        if model.hidden, let button = statusItem.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        else { popover.show(relativeTo: NSRect(x: 35 * model.preferences.scale, y: 20 * model.preferences.scale, width: 185 * model.preferences.scale, height: 190 * model.preferences.scale), of: desktop.petView, preferredEdge: .minX) }
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        quota.refreshIfStale()
        installPopoverDismissal()
    }
    private func installPopoverDismissal() {
        removePopoverDismissal()
        // Accessory apps can retain their popover without a resign-active
        // callback. A different foreground application also dismisses it.
        popoverActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.popover?.performClose(nil) }
        }
        popoverGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.dismissPopoverOutside(event) }
        }
        popoverLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown {
                    if event.keyCode == 53 { self?.popover?.performClose(nil) }
                } else { self?.dismissPopoverOutside(event) }
            }
            return event
        }
    }
    private func dismissPopoverOutside(_ event: NSEvent) {
        guard let popover, popover.isShown, let window = popover.contentViewController?.view.window else { return }
        let mouse = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        guard !window.frame.contains(mouse) else { return }
        let local = NSPoint(x: (mouse.x - desktop.panel.frame.minX) / model.preferences.scale,
                            y: (mouse.y - desktop.panel.frame.minY) / model.preferences.scale)
        // The pet itself toggles the card on mouse-up. Every other click passes through unchanged.
        guard !desktop.scene.containsCharacter(local) else { return }
        popover.performClose(nil)
    }
    func applicationDidResignActive(_ notification: Notification) { popover?.performClose(nil) }
    private func removePopoverDismissal() {
        if let popoverGlobalMonitor { NSEvent.removeMonitor(popoverGlobalMonitor) }
        if let popoverLocalMonitor { NSEvent.removeMonitor(popoverLocalMonitor) }
        if let popoverActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(popoverActivationObserver) }
        popoverActivationObserver = nil
        popoverGlobalMonitor = nil; popoverLocalMonitor = nil
    }
    func popoverDidClose(_ notification: Notification) { desktop.cardOpen = false; popover = nil; removePopoverDismissal() }
    func windowWillClose(_ notification: Notification) { if notification.object as? NSWindow === settingsWindow { settingsWindow?.contentView = nil; settingsWindow = nil; assets.purge(except: [desktop.scene.activeAtlas]) } }
    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] allowed, error in
            if !allowed { DispatchQueue.main.async { self?.model.notice = "系统通知未开启；额度卡片仍会正常显示。" } }
        }
    }
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    private func exercise() {
        let actions: [(Double, @MainActor @Sendable () -> Void)] = [
            (2, { [weak self] in self?.desktop.startStory(.eating, manual: true) }),
            (11, { [weak self] in self?.desktop.startStory(.begging, manual: true) }),
            (17, { [weak self] in self?.desktop.startStory(.explosion, manual: true) }),
            (25, { [weak self] in self?.desktop.exerciseThrow() }),
            (43, { [weak self] in self?.openSettings() }),
            (50, { [weak self] in self?.settingsWindow?.close() }),
            (55, { [weak self] in self?.toggleQuota() }),
            (60, { [weak self] in self?.popover?.performClose(nil) }),
            (62, { [weak self] in self?.desktop.exerciseGaze(seconds: 22, soot: true) }),
            (85, { [weak self] in self?.desktop.exerciseWave() })
        ]
        let rounds = value(after: "--exercise-rounds").flatMap(Int.init) ?? 1
        for round in 0..<min(20, max(1, rounds)) {
            for (delay, action) in actions { DispatchQueue.main.asyncAfter(deadline: .now() + Double(round) * 90 + delay, execute: action) }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { removePopoverDismissal(); quota.stop(); desktop.stop(); metrics?.stop(); hotkeys?.stop(); memorySource?.cancel(); model.save() }
}

@MainActor final class Hotkeys {
    private let model: AppModel
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var signature = ""
    private let jump: () -> Void
    init(model: AppModel, jump: @escaping () -> Void) {
        self.model = model; self.jump = jump
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let target = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { target.invoke(id.id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        register()
    }
    func register() {
        let p = model.preferences
        let key = "\(p.shortcutVisibility)-\(p.shortcutQuiet)-\(p.shortcutPause)-\(p.visibilityKey)-\(p.quietKey)-\(p.pauseKey)-\(p.jumpShortcut)-\(p.jumpKey)"
        guard signature != key else { return }; signature = key
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll()
        let codes: [String: Int] = ["A":0,"B":11,"C":8,"D":2,"E":14,"F":3,"G":5,"H":4,"I":34,"J":38,"K":40,"L":37,"M":46,"N":45,"O":31,"P":35,"Q":12,"R":15,"S":1,"T":17,"U":32,"V":9,"W":13,"X":7,"Y":16,"Z":6]
        let definitions: [(Bool, Int, UInt32)] = [(p.shortcutVisibility, codes[p.visibilityKey] ?? 3, 1), (p.shortcutQuiet, codes[p.quietKey] ?? 46, 2), (p.shortcutPause, codes[p.pauseKey] ?? 35, 3), (p.jumpShortcut, codes[p.jumpKey] ?? 38, 4)]
        for (enabled, code, identifier) in definitions where enabled {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x44465955, id: identifier), GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { refs.append(reference) } else { model.notice = "有一个快捷键已被其他应用占用，可在通用设置中更换按键或关闭。" }
        }
    }
    private func invoke(_ id: UInt32) { switch id { case 1: model.hidden.toggle(); case 2: model.quiet.toggle(); case 3: model.paused.toggle(); case 4: jump(); default: break } }
    func stop() { refs.forEach { UnregisterEventHotKey($0) }; if let handler { RemoveEventHandler(handler) } }
}

@MainActor final class MetricsRecorder {
    private var timer: Timer?
    private var file: FileHandle?
    private let model: AppModel
    private let assets: AssetStore
    private let desktop: DesktopController
    private let quotaShown: () -> Bool
    private var priorCPU: Double?
    private var priorTime: Double?
    init(folder: URL, model: AppModel, assets: AssetStore, desktop: DesktopController, quotaShown: @escaping () -> Bool) {
        self.model = model; self.assets = assets; self.desktop = desktop
        self.quotaShown = quotaShown
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("runtime-\(ProcessInfo.processInfo.processIdentifier).jsonl")
        FileManager.default.createFile(atPath: path.path, contents: nil); file = try? FileHandle(forWritingTo: path)
        sample(); timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
    }
    private func sample() {
        var info = task_vm_info_data_t(); var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return }
        let memory = Double(info.phys_footprint) / 1_000_000
        model.diagnostics = String(format: "主进程 %.1f MB · 已载入 %d 张图集", memory, assets.loadedAtlasCount)
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let stamp = ProcessInfo.processInfo.systemUptime
        let cpuPercent = priorTime.map { (cpu - (priorCPU ?? cpu)) / max(0.001, stamp - $0) * 100 } ?? 0
        priorCPU = cpu; priorTime = stamp
        let sample: [String: Any] = ["time": Date().timeIntervalSince1970, "uptime": ProcessInfo.processInfo.systemUptime,
            "pid": ProcessInfo.processInfo.processIdentifier, "physicalFootprintBytes": info.phys_footprint,
            "residentBytes": info.resident_size, "atlases": assets.loadedAtlasCount, "status": model.status,
            "scope": "main-process-only", "cpuPercentOneCore": cpuPercent, "rendererKicks": desktop.rendererKicks,
            "renderPaused": desktop.petView.renderingPaused, "preferredFPS": desktop.petView.preferredFramesPerSecond,
            "bowlRenderPaused": desktop.bowlView.renderingPaused, "bowlQuotaDisplayed": desktop.bowlScene.quotaIsDisplayed,
            "scenePaused": desktop.scene.isPaused, "frameCount": desktop.frameCount,
            "activeFrameFPS": desktop.frameTiming.framesPerSecond, "frameP95Milliseconds": desktop.frameTiming.p95Milliseconds,
            "quotaShown": quotaShown(), "hidden": model.hidden, "interactionPaused": model.paused,
            "gazeDirection": desktop.scene.look, "headTurning": desktop.isTurningHead,
            "gazeDirectionsSeen": desktop.scene.renderedGazeDirections.sorted(),
            "clip": desktop.scene.activeAtlas, "sootLevel": desktop.scene.sootLevel]
        if var data = try? JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys]) { data.append(10); try? file?.write(contentsOf: data) }
    }
    func stop() { timer?.invalidate(); try? file?.close() }
}
