import AppKit
import SpriteKit
import Combine
import DafeiyuCore

@MainActor final class DesktopController {
    enum Activity { case idle, waving, story(Story), chasing, recovering, jumping, draggingBody, flinching, falling, dozing, surprised, hanging, sitting, wandering }
    enum Food { case text(String), file(String), image, link(String) }
    enum BowlHit { case head, body, feet }
    let model: AppModel
    let assets: AssetStore
    let panel: PetPanel
    let bowlPanel: PetPanel
    let petView: PetView
    let bowlView: PetView
    let scene: PetScene
    let bowlScene: BowlScene
    var showQuota: (() -> Void)?
    var showSettings: (() -> Void)?
    var cardOpen = false { didSet { if cardOpen { finishActivity() }; scheduleAmbient() } }
    private var timer: Timer?
    private var tokens: [NSObjectProtocol] = []
    private var subscriptions = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var localPointerMonitor: Any?
    private var activity: Activity = .idle { didSet { updateFrameBudget() } }
    private var activityStart = 0.0
    private var activityEnd = 0.0
    private var nextAmbient = 0.0
    private var nextBlink = 0.0
    private var blinkStart: Double?
    private var awakeUntil = 0.0
    private var lastFrame = 0.0
    private(set) var frameCount = 0
    private(set) var frameTiming = FrameTiming()
    private var lastPurge = 0.0
    private var lastHover = false
    private var lastWave = 0.0
    private var nextBreath = 0.0
    private var breathStart: Double?
    private var startledUntil = 0.0
    private var eatingStartled = false
    private var puffShown = false
    private var emotionUntil = 0.0
    private var speechCue: SpeechCue?
    private var speechVariants: [SpeechCue: Int] = [:]
    private var wiping = false
    private var lastWipe = Vector()
    private var runPhase = 0.0
    private var bodyDragLastMovement = -Double.infinity
    private var bodyDragSampleTime = 0.0
    private var bodyDragSpeed = 0.0
    private var bodyDragFacingLeft = false
    private var flinchKind = BowlHit.body
    private var flinchBase = Vector()
    private var bowlHitCooldown = 0.0
    private var reachingUp = false
    private var kickedThisChase = false
    private var chaseBoost = 1.0
    private var stealStart = 0.0
    private var steals: [Double] = []
    private var afterFlinchCue: SpeechCue?
    private var perch: WindowLedge.Window?
    private var lastPerchCheck = 0.0
    private var fallSpeed = 0.0
    private var fallWindows: [WindowLedge.Window] = []
    private var hangEdge: WindowLedge.Window?
    /// Hand line of the hanging frames, in points above the cell bottom (Art/motion-v2: the
    /// fists start about 170 px below the top of the 576 px cell; the edge crosses them 12 px lower).
    private let gripHeight = 197.0
    private var refill = RefillDetector()
    /// Sitting cells put the window top 116 px above the cell bottom, so the panel drops by 58 pt.
    private let sitDrop = 58.0
    private var idleSince = ProcessInfo.processInfo.systemUptime
    private var welcomeAfterRecovery = false
    /// Seconds standing still on a window before she sits down (a test hook).
    var sitAfter = 20.0
    private enum WanderPhase { case walking, climbing, looking }
    private var wanderPlan: WanderPlan?
    private var wanderPhase = WanderPhase.walking
    private var wanderPhaseStart = 0.0
    private var walkClock = 0.0
    private var nextWander = ProcessInfo.processInfo.systemUptime + 90
    /// Feet stay this far from a wall while climbing it (the climbing cells put the wall 54 pt from centre).
    private let climbStandOff = 54.0
    /// Test hook for the Dock items (normally read through Accessibility).
    var iconSource: (() -> [(name: String, frame: CGRect)])?
    /// Top of her head above her feet in the standing frames (look-0 starts 26 px below the 416 px cell top).
    private let headHeight = 196.0
    private var dozeStart = 0.0
    private var lastIdleCheck = 0.0
    private var userIdle = 0.0
    private var petting = PettingDetector()
    private var pettingCooldown = 0.0
    private var breakClock = BreakClock()
    private var breakDue = false
    private var agents = AgentActivity()
    private let agentCPU = AgentCPU()
    private var agentEvent: AgentActivity.Event?
    private var lastAgentCheck = 0.0
    private var greetedDay = -1
    private var lastNightNote = -Double.infinity
    private var lastRhythmCheck = 0.0
    private var literalSpeech: String?
    private var lastFrameSeen = (count: 0, time: 0.0)
    private var lastRendererKick = -Double.infinity
    private(set) var rendererKicks = 0
    /// Seconds since the last keyboard/mouse input. Needs no input-monitoring permission.
    var idleSource: () -> Double = { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) }
    /// Test hooks: other apps' windows (Cocoa coordinates) and agent CPU share.
    var windowSource: (() -> [WindowLedge.Window])?
    var agentSource: (() -> Double)?
    /// Injectable for tests; decides the occasional accidental kick.
    var random: () -> Double = { Double.random(in: 0..<1) }
    private var quotaProviders: [String: ProviderStatus] = [:]
    private var lastBowlQuotaCheck = -Double.infinity
    private var bowlRedrawUntil = 0.0
    private var sleeping = false
    private var fullscreen = false
    private var position = Vector()
    private var velocity = Vector()
    private var jumpStart = Vector()
    private var jumpEnd = Vector()
    private var bowlPosition = Vector()
    private var bowlMotion: BowlMotion?
    private var bowlVisible = false
    private var bowlDetached = false
    private var dragging: PetView.Target?
    private var pressPoint = Vector()
    private var pressPosition = Vector()
    private var didDrag = false
    private var throwSampler = ThrowSampler()
    private var gaze = GazeSelector()
    private var gazeFollower = GazeFollower()
    private var gazeDemoStart = 0.0
    private var gazeDemoUntil = 0.0
    private var gazeDemoUpperLeftOnly = false
    var isTurningHead: Bool { gazeFollower.isTurning }
    private var bag = StoryBag()
    // 0 means the primary display. NSScreen.main follows keyboard focus across
    // displays, which split the pet and its bowl onto different screens.
    private var currentScreen: NSScreen { NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == model.preferences.displayID } ?? NSScreen.screens.first ?? NSScreen.main! }
    private var scale: Double { model.preferences.scale }
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var reducedMotion: Bool { model.preferences.respectReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var inactive: Bool { sleeping || model.hidden || (fullscreen && model.preferences.hideInFullscreen) }
    private var bodyDragAnimating: Bool { model.preferences.runWhileDragging && !reducedMotion && now - bodyDragLastMovement < 0.16 }
    private var bounds: MotionBounds {
        let rect = currentScreen.visibleFrame
        // Her head reaches up to the menu bar. Only the bubble space above it may pass
        // under the menu bar; PetPanel refuses macOS's own push-down, so the pet stays
        // where the bowl expects her.
        return .init(minX: rect.minX + 100 * scale, minY: rect.minY + 4, maxX: rect.maxX - 100 * scale, maxY: rect.maxY - headHeight * scale)
    }
    init(model: AppModel, assets: AssetStore) {
        self.model = model; self.assets = assets
        scene = PetScene(assets: assets)
        bowlScene = BowlScene(assets: assets)
        panel = PetPanel(size: CGSize(width: 256, height: 288)); bowlPanel = PetPanel(size: CGSize(width: 128, height: 128))
        petView = PetView(frame: panel.contentView!.bounds, target: .body)
        bowlView = PetView(frame: bowlPanel.contentView!.bounds, target: .bowl)
        panel.contentView = petView; bowlPanel.contentView = bowlView
        petView.presentScene(scene); bowlView.presentScene(bowlScene)
        petView.owner = self; bowlView.owner = self
        scene.onFrame = { [weak self] time in self?.frame(time) }
        if let x = model.preferences.positionX, let y = model.preferences.positionY { position = bounds.clamp(.init(x, y)) }
        else { position = .init(bounds.maxX - 40, bounds.minY + 20) }
        model.onPreferences = { [weak self] in self?.applyPreferences() }
        model.onPreview = { [weak self] story in self?.startStory(story, manual: true) }
        model.onSpeechPreview = { [weak self] cue in self?.previewSpeech(cue) }
        model.onGazePreview = { [weak self] in self?.exerciseGaze(seconds: 12) }
        model.onResetPosition = { [weak self] in self?.resetPosition() }
        model.onVisibility = { [weak self] in self?.updateVisibility() }
        model.$paused.dropFirst().sink { [weak self] paused in DispatchQueue.main.async { self?.pauseChanged(paused) } }.store(in: &subscriptions)
        model.$quiet.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.finishActivity(); self?.scheduleAmbient() } }.store(in: &subscriptions)
        model.$hidden.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.updateVisibility() } }.store(in: &subscriptions)
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            tokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.systemWillSleep() } })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            tokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.systemDidWake() } })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.applyPreferences() } })
        tokens.append(ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.detectFullscreen() } })
        tokens.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.detectFullscreen() } })
        nextBlink = now + 4; nextBreath = now + 8; scheduleAmbient(); applyPreferences(); scene.useGaze = true; wake(for: 0.3)
        assets.preloadGaze(); startPulse()
        installPointerMonitors()
        // Back on the window she was standing on when the app last quit, if it is still there.
        DispatchQueue.main.async { [weak self] in self?.tryPerch() }
    }
    func systemWillSleep() { sleeping = true; finishActivity(); updateVisibility() }
    func systemDidWake() { sleeping = false; scheduleAmbient(); updateVisibility() }
    private func startPulse() {
        guard timer == nil, !inactive else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pulse() } }
        timer?.tolerance = 0.025
    }
    func applyPreferences() {
        let p = model.preferences
        scene.emotionStrength = p.emotionStrength
        refreshSpeech()
        if !p.gaze { gazeFollower.aim(at: 0, immediately: true); scene.look = 0 }
        panel.level = p.desktopOnly ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1) : .floating
        bowlPanel.level = panel.level
        let behavior: NSWindow.CollectionBehavior = p.allSpaces ? [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary] : [.ignoresCycle, .fullScreenAuxiliary]
        panel.collectionBehavior = behavior; bowlPanel.collectionBehavior = behavior
        updateFrameBudget(); position = bounds.clamp(position)
        if !bowlDetached { bowlPosition = restBowl() }
        refreshBowlQuota(); placeWindows(); wake(for: 0.2); updateVisibility(); scheduleAmbient()
    }
    func observeQuota(_ quota: QuotaStore) {
        quota.$providers.sink { [weak self] providers in
            self?.quotaProviders = providers; self?.refreshBowlQuota()
        }.store(in: &subscriptions)
    }
    private func refreshBowlQuota() {
        lastBowlQuotaCheck = now
        let p = model.preferences, state = quotaProviders[p.bowlQuotaSource]
        let reading = BowlQuotaReading.make(preferences: p, snapshot: state?.snapshot, loading: state?.loading == true, failed: state?.error != nil)
        if reading != nil { bowlVisible = true; if !inactive && !bowlPanel.isVisible { bowlPanel.orderFrontRegardless() } }
        bowlView.toolTip = reading?.detail ?? "饭盆：拖走后大肥鱼会追过来"
        bowlView.setAccessibilityLabel(bowlView.toolTip)
        let changed = bowlScene.setQuota(reading, showLabel: p.bowlQuotaLabel)
        if let from = refill.update(key: p.bowlQuotaSource + "|" + p.bowlQuotaWindow, fraction: reading?.fraction) { refilled(from: from) }
        else if changed { redrawBowl() }
    }
    /// Quota reset on the bowl's source: the rice pours in and she is delighted.
    private func refilled(from: Double) {
        var delight = model.preferences.resetSurprise && !model.paused && !inactive && !model.quiet && !cardOpen && dragging == nil
        switch activity { case .idle, .dozing, .waving, .recovering, .sitting: break; default: delight = false }
        let animate = delight && !reducedMotion && assets.clips["surprised"] != nil
        if animate { finishActivity() }
        bowlScene.pourRice(from: from, duration: 1.6); redrawBowl(for: 1.9)
        guard delight else { return }
        guard animate else { scene.setEmotion("✨"); say(.refilled); emotionUntil = now + 3; wake(for: 0.3); return }
        activity = .surprised; activityStart = now; activityEnd = now + 3.1
        scene.useGaze = true; scene.look = 0; gazeFollower.aim(at: 0, immediately: true)
        model.status = "饭票回来啦"; wake(for: 3.3)
    }
    private func redrawBowl(for seconds: Double = 0.3) {
        bowlRedrawUntil = max(bowlRedrawUntil, now + seconds)
        if bowlVisible && !inactive { bowlView.renderingPaused = false }
    }
    private func updateFrameBudget() {
        let p = model.preferences
        let low = p.performance == .economy || (p.automaticEnergySaving && ProcessInfo.processInfo.isLowPowerModeEnabled)
        let active: Bool
        if case .idle = activity { active = gazeFollower.isTurning || gazeDemoUntil > now || blinkStart != nil || breathStart != nil }
        else if case .draggingBody = activity { active = bodyDragAnimating }
        else if case .dozing = activity { active = breathStart != nil }
        else { active = true }
        var dozing = false; if case .dozing = activity { dozing = true }
        let fps = active ? min(p.frameLimit, low || dozing ? 30 : 60) : low ? 10 : 15
        // Avoid reconfiguring SpriteKit's display link every time a direction or
        // eyelid changes. Static frames are gated separately from active cadence.
        if petView.preferredFramesPerSecond != fps { petView.preferredFramesPerSecond = fps }
        if bowlView.preferredFramesPerSecond != fps { bowlView.preferredFramesPerSecond = fps }
    }
    func resetPosition() { finishActivity(); position = .init(bounds.maxX - 40, bounds.minY + 20); placeWindows(); savePosition() }
    private func savePosition() { model.preferences.positionX = position.x; model.preferences.positionY = position.y }
    private func pointer() -> Vector { let p = NSEvent.mouseLocation; return .init(p.x, p.y) }
    private func wake(for seconds: Double) {
        awakeUntil = max(awakeUntil, now + seconds)
        if !inactive && !model.paused {
            if petView.renderingPaused { frameTiming.resumeAfterIdle() }
            petView.renderingPaused = false
        }
    }
    private func scheduleAmbient() { nextAmbient = now + Double.random(in: model.preferences.ambientMin...max(model.preferences.ambientMin, model.preferences.ambientMax)) }
    private func say(_ cue: SpeechCue?) {
        if let cue, cue != speechCue { speechVariants[cue] = (speechVariants[cue] ?? -1) + 1 }
        if cue != nil { literalSpeech = nil }
        speechCue = cue; refreshSpeech()
    }
    private func refreshSpeech() {
        scene.say(speechCue.map { model.preferences.speech(for: $0, variant: speechVariants[$0] ?? 0) } ?? literalSpeech ?? "")
    }
    private func previewSpeech(_ cue: SpeechCue) {
        finishActivity(); say(cue); emotionUntil = now + 4; wake(for: 4.2)
    }
    private func installPointerMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { guard let self else { return }; self.updateGazeTarget(mouse: self.location(of: event)) }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { guard let self else { return }; self.updateGazeTarget(mouse: self.location(of: event)) }
            return event
        }
    }
    private func updateGazeTarget(mouse: Vector, preview: Bool = false) {
        guard !inactive, !model.paused, model.preferences.gaze, case .idle = activity else { return }
        guard preview || gazeDemoUntil <= now else { return }
        let local = CGPoint(x: (mouse.x - panel.frame.minX) / scale, y: (mouse.y - panel.frame.minY) / scale)
        let overBody = !preview && (scene.containsCharacter(local) || wiping)
        let direction = gaze.update(dx: mouse.x - position.x, dy: mouse.y - (position.y + 110 * scale), overBody: overBody)
        if direction != gazeFollower.target || !scene.useGaze || overBody && gazeFollower.isTurning {
            gazeFollower.aim(at: direction, immediately: reducedMotion || overBody)
            scene.useGaze = true; scene.look = gazeFollower.direction
            updateFrameBudget(); wake(for: 0.25)
        }
    }
    private func pulse() {
        guard !inactive else { return }
        watchRenderer()
        if now - lastBowlQuotaCheck > 5 { refreshBowlQuota() }
        if now > bowlRedrawUntil, bowlMotion == nil, dragging != .bowl {
            switch activity { case .idle, .draggingBody: bowlView.renderingPaused = true; default: break }
        }
        let mouse = pointer()
        if dragging == nil {
            let local = CGPoint(x: (mouse.x - panel.frame.minX) / scale, y: (mouse.y - panel.frame.minY) / scale)
            let hit = scene.containsCharacter(local)
            panel.ignoresMouseEvents = !hit
            let bowlLocal = Vector((mouse.x - bowlPosition.x) / scale, (mouse.y - bowlPosition.y) / scale)
            bowlPanel.ignoresMouseEvents = !(bowlVisible && abs(bowlLocal.x) < 46 && abs(bowlLocal.y) < 35)
            if hit && !lastHover && gazeDemoUntil <= now && model.preferences.wave && now - lastWave > 8 && !model.paused && !cardOpen, case .idle = activity {
                activity = .waving; activityStart = now; activityEnd = now + 2.6; scene.play("waving", duration: 2.6); lastWave = now; wake(for: 2.7)
                say(.greeting)
            }
            lastHover = hit
        }
        guard !model.paused else { return }
        if case .sitting = activity { sitTick() }
        companionTick(mouse: mouse)
        if case .idle = activity {
            updateGazeTarget(mouse: mouse)
            if emotionUntil > 0 && now > emotionUntil { scene.faceReaction = 0; scene.setEmotion(""); say(scene.sootLevel > 0 ? .wipeRequest : nil); emotionUntil = 0; wake(for: 0.1) }
            if now >= nextBreath && !reducedMotion && !cardOpen {
                breathStart = now; nextBreath = now + (model.preferences.performance == .economy ? 30 : 16); updateFrameBudget(); wake(for: 2.5)
            }
            if now >= nextBlink && blinkStart == nil { blinkStart = now; updateFrameBudget(); wake(for: 0.3) }
            if gazeDemoUntil <= now && !model.quiet && !cardOpen && dragging == nil && !lastHover && now >= nextAmbient {
                let mood = quotaMoodStory()
                if let story = mood ?? bag.next(enabled: model.preferences.stories) {
                    startStory(story); if mood == .begging, case .story = activity { say(.hungry) }
                }
                scheduleAmbient()
            }
            if gazeDemoUntil <= now && model.preferences.following && !model.quiet && !cardOpen && (mouse - position).length > 200 { beginChasing() }
        }
        if now - lastPurge > 10 { assets.purge(except: [scene.activeAtlas]); lastPurge = now }
        // First texture upload can outlast the initial wake window under GPU
        // pressure. Never gate the renderer before it has produced a frame.
        let resting: Bool
        switch activity { case .idle, .sitting: resting = true; case .dozing: resting = breathStart == nil; case .draggingBody: resting = !bodyDragAnimating && scene.useGaze; default: resting = false }
        // A thrown bowl is stepped by the pet's frame loop; never freeze it mid-air.
        if frameCount > 0, now > awakeUntil, resting, bowlMotion == nil, blinkStart == nil, !gazeFollower.isTurning, gazeDemoUntil <= now {
            petView.renderingPaused = true
            if now > bowlRedrawUntil { bowlView.renderingPaused = true }
        }
    }
    private func frame(_ timestamp: Double) {
        frameCount += 1
        frameTiming.record(timestamp)
        let dt = min(0.05, max(0, lastFrame == 0 ? 1.0 / 30 : timestamp - lastFrame)); lastFrame = timestamp
        guard !model.paused && !inactive else { return }
        if let start = blinkStart {
            let elapsed = now - start
            scene.blink = elapsed < 0.035 ? 1 : elapsed < 0.07 ? 2 : elapsed < 0.15 ? 3 : elapsed < 0.19 ? 2 : elapsed < 0.22 ? 1 : 0
            if elapsed >= 0.22 { blinkStart = nil; nextBlink = now + Double.random(in: 3...7); updateFrameBudget() }
        }
        switch activity {
        case .draggingBody:
            updateBodyDragPose(dt: dt)
        case .idle:
            if gazeDemoUntil > now {
                let elapsed = now - gazeDemoStart
                let angle = gazeDemoUpperLeftOnly
                    ? (24 + 4 * (1 - cos(elapsed * 2 * .pi / 8))) / 32 * 2 * .pi
                    : elapsed * 2 * .pi / 6
                updateGazeTarget(mouse: position + Vector(sin(angle) * 400, 110 * scale + cos(angle) * 400), preview: true)
            } else {
                if gazeDemoUntil > 0 { gazeDemoUntil = 0; updateFrameBudget() }
                updateGazeTarget(mouse: pointer())
            }
            if model.preferences.gaze {
                let wasTurning = gazeFollower.isTurning
                gazeFollower.advance(dt: dt); scene.look = gazeFollower.direction
                if wasTurning && !gazeFollower.isTurning { updateFrameBudget(); wake(for: 0.1) }
            }
            if let start = breathStart {
                let t = (now - start) / 2.4
                scene.body.yScale = 1 + sin(t * .pi) * 0.012
                if t >= 1 { breathStart = nil; scene.body.yScale = 1; updateFrameBudget() }
            }
        case .waving: if now >= activityEnd { finishActivity() }
        case .story(let story):
            let fraction = min(1, max(0, (now - activityStart) / max(0.1, activityEnd - activityStart)))
            if story == .explosion {
                if fraction < 0.2 { bowlPosition = heldBowl(); scene.frameOverride = 0 }
                else if fraction < 0.78 {
                    let t = (fraction - 0.2) / 0.58
                    let head = position + Vector(0, 185 * scale)
                    let available = max(0, currentScreen.visibleFrame.maxY - head.y - 64 * scale)
                    bowlPosition = heldBowl() + (head - heldBowl()) * t + Vector(0, sin(t * .pi) * available * model.preferences.explosionHeight)
                    bowlScene.bowl.zRotation = t * .pi * 2
                    scene.frameOverride = t < 0.25 ? 1 : t < 0.65 ? 2 : 3
                    if !puffShown { scene.puff(strength: model.preferences.effects * (model.preferences.performance == .economy ? 0.4 : 1)); puffShown = true }
                } else if fraction < 0.88 {
                    bowlPosition = position + Vector(0, 185 * scale); bowlScene.bowl.zRotation = 0
                    scene.frameOverride = fraction < 0.83 ? 4 : 5; scene.sootLevel = 1
                    scene.body.yScale = 0.98
                } else {
                    let t = (fraction - 0.88) / 0.12
                    bowlPosition = position + Vector(0, (185 - 109 * t) * scale)
                    scene.frameOverride = t < 0.5 ? 6 : 7; scene.body.yScale = 1
                }
            } else {
                bowlPosition = heldBowl()
                if story == .eating {
                    if lastHover && !eatingStartled && fraction < 0.8 {
                        eatingStartled = true; startledUntil = now + 1; scene.setEmotion("!"); say(.caughtEating)
                    }
                    if now < startledUntil {
                        activityStart += dt; activityEnd += dt; scene.clipStarted += dt
                        scene.frameOverride = 0
                    } else {
                        scene.frameOverride = nil; scene.setEmotion(""); say(fraction > 0.8 ? .lastBite : nil)
                        scene.body.yScale = 1 + sin(fraction * .pi * 16) * 0.008
                    }
                } else { bowlPosition.y += sin(now * 5) * 1.5 }
            }
            if now >= activityEnd { finishActivity() }
        case .chasing:
            let target = bowlDetached ? bowlPosition - Vector(0, 75 * scale) : pointer() - Vector(0, 85 * scale)
            let offset = bounds.clamp(target) - position
            // A bowl still held by the pointer but inside her reach is snatched back.
            if dragging == .bowl && bowlDetached && now - stealStart > 0.6 && bowlWithinReach { snatchBowl(); break }
            if bowlDetached && offset.length < (reachingUp ? 40 : 24) * scale {
                // Arrived under a bowl she cannot reach (held up high or still flying): stand and ask for it.
                velocity = .init()
                if !reachingUp { reachingUp = true; scene.play("waiting", duration: 1.01, loop: true) }
            } else {
                reachingUp = false
                let desired = offset.limited(to: 200 * model.preferences.chaseSpeed * chaseBoost)
                velocity = velocity + (desired - velocity) * min(1, dt * 5)
                position = bounds.clamp(position + velocity * dt)
                let name = velocity.x < -10 ? "running-left" : "running-right"
                if scene.clip != name { scene.play(name, loop: true) }
                runPhase += dt * min(1.8, max(0.35, velocity.length / 145))
                if let count = assets.clips["jog"]?.frames { scene.frameOverride = Int(runPhase / 0.8 * Double(count)) % count }
            }
            if !bowlDetached && offset.length < 22 { finishActivity() }
            if dragging != .bowl && bowlDetached && (bowlMotion?.velocity.length ?? 0) < 300 && (bowlPosition - heldBowl()).length < 80 * scale {
                let canKick = model.preferences.kickBowl && !kickedThisChase && velocity.length > 60 * scale && activityEnd - now > 3
                if canKick && random() < 0.3 { kickBowl() } else { returnBowl() }
            }
            else if now >= activityEnd { recover(angry: chaseBoost > 1) }
        case .flinching:
            let t = min(1, (now - activityStart) / max(0.1, activityEnd - activityStart))
            scene.useGaze = true; scene.look = 0; scene.frameOverride = nil
            switch flinchKind {
            case .head: scene.faceReaction = 3; scene.body.yScale = 1 - 0.07 * sin(min(1, t * 2.5) * .pi)
            case .body: scene.faceReaction = 0; scene.body.yScale = 1 + 0.03 * sin(min(1, t * 2) * .pi)
            case .feet: scene.faceReaction = 2; position = flinchBase + Vector(0, reducedMotion ? 0 : sin(t * .pi) * 26 * scale)
            }
            if t >= 1 {
                scene.body.yScale = 1; scene.faceReaction = 0; position = flinchBase
                if bowlDetached { beginChasing(); if chaseBoost > 1 { say(.furious) } }
                else { finishActivity(); if let cue = afterFlinchCue { say(cue); emotionUntil = now + 2.2 } }
                afterFlinchCue = nil
            }
        case .recovering:
            if now >= activityEnd { finishActivity(); if welcomeAfterRecovery { welcomeAfterRecovery = false; welcome() } }
        case .sitting: sitTick()
        case .wandering: wanderStep(dt: dt)
        case .dozing where assets.clips["sleeping"] != nil && !reducedMotion:
            // Closed eyes for a moment, kneel, then lie on her front; each breath lifts her back.
            let elapsed = now - dozeStart
            if elapsed < 0.5 { scene.useGaze = true; scene.faceReaction = 3; break }
            if scene.useGaze { scene.play("sleeping") }
            var pose = elapsed < 1 ? 0 : 1
            if let start = breathStart {
                let t = (now - start) / 2.4
                pose = [1, 2, 3, 2, 1][min(4, Int(t * 5))]
                if t >= 1 { breathStart = nil; updateFrameBudget() }
            }
            scene.frameOverride = pose
        case .dozing:
            scene.useGaze = true; scene.faceReaction = 3
            if let start = breathStart {
                let t = (now - start) / 2.4
                scene.body.yScale = 1 + sin(t * .pi) * 0.015
                if t >= 1 { breathStart = nil; scene.body.yScale = 1; updateFrameBudget() }
            }
        case .falling:
            fallSpeed -= 2200 * dt
            let next = max(bounds.minY, position.y + fallSpeed * dt)
            scene.useGaze = true; scene.look = 0; scene.faceReaction = 2
            if let ledge = WindowLedge.landing(feetX: position.x, fromY: position.y, toY: next, windows: fallWindows), ledge.frame.maxY <= bounds.maxY {
                position.y = ledge.frame.maxY; land(on: ledge)
            } else if next <= bounds.minY { position.y = bounds.minY; land(on: nil) }
            else { position.y = next }
        case .surprised:
            // Stand still for a beat while the rice starts pouring, then the clasped-hands delight.
            let elapsed = now - activityStart, cuts = [0.3, 0.55, 1.0, 1.7, 2.4]
            if elapsed >= cuts[0] {
                if scene.useGaze { scene.play("surprised", duration: 2.8) }
                scene.frameOverride = cuts.lastIndex { elapsed >= $0 } ?? 0
            }
            if elapsed >= cuts[2] && speechCue != .refilled { scene.setEmotion("✨"); say(.refilled) }
            // Keep the same line on screen for a moment after she settles.
            if now >= activityEnd { finishActivity(); speechCue = .refilled; refreshSpeech(); emotionUntil = now + 2 }
        case .hanging:
            // Grabbing the edge carries momentum: two seconds of the big swing, then the gentle one.
            let swing = now - activityStart
            scene.frameOverride = swing < 2 ? Int(swing * 8) % 8 : 8 + Int((swing - 2) * 8) % 8
            if now >= activityEnd { letGo() }
            else if now - lastPerchCheck >= 0.5, let edge = hangEdge {
                lastPerchCheck = now
                // The window was moved, closed or minimised under her hands.
                if !windowList().contains(where: { $0.id == edge.id && abs($0.frame.maxY - edge.frame.maxY) < 2 && abs($0.frame.minX - edge.frame.minX) < 2 }) { letGo() }
            }
        case .jumping:
            let t = min(1, (now - activityStart) / 0.84)
            let eased = t * t * (3 - 2 * t)
            position = jumpStart + (jumpEnd - jumpStart) * eased + Vector(0, sin(t * .pi) * (reducedMotion ? 0 : 70))
            if t >= 1 { position = jumpEnd; finishActivity(); tryPerch(); savePosition() }
        }
        if var motion = bowlMotion, dragging != .bowl {
            let frame = currentScreen.visibleFrame
            motion.step(dt: dt, bounds: .init(minX: frame.minX + 64 * scale, minY: frame.minY + 37 * scale, maxX: frame.maxX - 64 * scale, maxY: frame.maxY - 64 * scale), bounce: model.preferences.bounce)
            if model.preferences.bowlHits, now > bowlHitCooldown, let zone = hitZone(motion), bowlHitsPet(zone, motion: &motion) {
                // Caught: the bowl is back in her arms.
            } else {
                bowlMotion = motion; bowlPosition = motion.position; bowlScene.bowl.zRotation = motion.angle
                if motion.settled { bowlMotion = nil; if case .idle = activity { beginChasing() } }
            }
        }
        if bowlVisible && !bowlDetached {
            if case .story = activity {} else if case .wandering = activity, wanderPhase == .climbing {   // the bowl waits on the floor
            } else { bowlPosition = restBowl() }
        }
        placeWindows()
    }
    private func heldBowl() -> Vector { position + Vector(0, 76 * scale) }
    private func restBowl() -> Vector {
        let screen = currentScreen.visibleFrame
        // While she hangs, the bowl waits on the window top beside her hands.
        let desired = position + Vector((isLyingDown ? 135 : 80) * scale, (hangEdge.map { $0.frame.maxY - position.y } ?? 0) + 30 * scale)
        // Leave room for the quota badge at the bottom and side of the screen.
        return Vector(min(screen.maxX - 60 * scale, max(screen.minX + 60 * scale, desired.x)),
                      min(screen.maxY - 64 * scale, max(screen.minY + 46 * scale, desired.y)))
    }
    private func placeWindows() {
        let density = currentScreen.backingScaleFactor
        func aligned(_ value: Double) -> Double { (value * density).rounded() / density }
        // Sitting on a window top, her lower legs hang below it: the panel drops while her position stays on the edge.
        let drop = isSitting ? sitDrop * scale : 0
        let bodyFrame = CGRect(x: aligned(position.x - 128 * scale), y: aligned(position.y - drop), width: aligned(256 * scale), height: aligned(288 * scale))
        let bowlFrame = CGRect(x: aligned(bowlPosition.x - 64 * scale), y: aligned(bowlPosition.y - 64 * scale), width: aligned(128 * scale), height: aligned(128 * scale))
        if panel.frame != bodyFrame { panel.setFrame(bodyFrame, display: false) }
        scene.bubbleCeiling = (currentScreen.visibleFrame.maxY - bodyFrame.minY) / scale
        if bowlPanel.frame != bowlFrame { bowlPanel.setFrame(bowlFrame, display: false) }
    }
    func startStory(_ story: Story, manual: Bool = false) {
        guard !model.paused, !inactive, dragging == nil, !cardOpen else { return }
        if reducedMotion { recover(angry: false); scene.setEmotion(story == .eating ? "🍚" : "✨"); return }
        finishActivity(); activity = .story(story); activityStart = now; eatingStartled = false; startledUntil = 0; puffShown = false
        let p = model.preferences
        activityEnd = now + (story == .eating ? p.eatingDuration : story == .explosion ? p.explosionDuration : 3)
        bowlVisible = true; bowlDetached = false; bowlPosition = heldBowl(); bowlScene.setRice(story == .eating)
        switch story {
        case .eating: scene.play("steel-eating", duration: p.eatingDuration); bowlScene.bowl.alpha = 0; model.status = "没有偷吃，只是尝一口"
        case .begging: scene.play("waiting", duration: 1.4, loop: true); model.status = "今天也想要白饭"
        case .explosion: scene.play("explosion-body", duration: p.explosionDuration); model.status = "饭盆准备起飞"
        }
        bowlPanel.orderFrontRegardless(); bowlView.renderingPaused = false; wake(for: activityEnd - now + 0.5)
    }
    private func finishActivity() {
        gazeDemoUntil = 0
        activity = .idle; velocity = .init(); bowlMotion = nil; bowlDetached = false; hangEdge = nil; idleSince = now
        reachingUp = false; kickedThisChase = false; chaseBoost = 1; literalSpeech = nil
        scene.frameOverride = nil; scene.body.yScale = 1; scene.faceReaction = 0; breathStart = nil
        scene.setEmotion(""); say(scene.sootLevel > 0 ? .wipeRequest : nil); scene.useGaze = true; scene.blink = 0; scene.suspended = false
        gazeFollower.aim(at: scene.look, immediately: true)
        bowlScene.bowl.zRotation = 0; bowlScene.bowl.alpha = 1; bowlPosition = restBowl(); model.status = "在这里陪你"
        bowlScene.resumeQuota(); redrawBowl()
        scheduleAmbient(); wake(for: 0.3); placeWindows()
    }
    private func beginChasing() {
        guard !model.paused, !cardOpen, !reducedMotion else { return }
        activity = .chasing; activityStart = now; activityEnd = now + model.preferences.chaseDuration
        scene.play("running-right", loop: true)
        scene.setEmotion(model.preferences.anger ? "💢" : "!"); model.status = "把饭盆还给我嘛"
        say(.chasing)
        wake(for: model.preferences.chaseDuration + 1)
    }
    private func recover(angry: Bool) {
        activity = .recovering; activityStart = now; activityEnd = now + model.preferences.recoveryDuration
        velocity = .init(); scene.useGaze = true
        scene.setEmotion(angry && model.preferences.anger ? "💢" : model.preferences.tears ? "💧" : "")
        say(.disappointed)
        model.status = "歇一会儿，等你回来"; wake(for: model.preferences.recoveryDuration + 0.2)
    }
    private func returnBowl() {
        bowlDetached = false; bowlMotion = nil; finishActivity()
        if model.preferences.guarding {
            activity = .recovering; activityEnd = now + 2
            scene.play("steel-eating", duration: 2); scene.frameOverride = 0
            bowlPosition = heldBowl(); bowlScene.bowl.alpha = 0
            scene.setEmotion("♡"); say(.guarding); model.status = "抱紧饭盆"; wake(for: 2.1)
        }
    }
    private var bowlWithinReach: Bool {
        let local = CGPoint(x: (bowlPosition.x - panel.frame.minX) / scale, y: (bowlPosition.y - panel.frame.minY) / scale)
        return scene.containsCharacter(local) || (bowlPosition - heldBowl()).length < 70 * scale
    }
    private func snatchBowl() {
        dragging = nil; throwSampler = ThrowSampler()
        returnBowl(); say(.snatched)
        if !model.preferences.guarding { scene.setEmotion("!"); emotionUntil = now + 2 }
    }
    /// Which part of her silhouette (slightly padded by the bowl) an incoming bowl touches.
    private func hitZone(_ motion: BowlMotion) -> BowlHit? {
        // Never interrupt a jump or a body drag; she would be left hanging mid-air.
        switch activity { case .jumping, .draggingBody, .flinching, .hanging, .sitting: return nil; default: guard dragging == nil else { return nil } }
        let x = (motion.position.x - position.x) / scale, y = (motion.position.y - position.y) / scale
        let dx = x / 105, dy = (y - 108) / 119
        guard dx * dx + dy * dy <= 1 else { return nil }
        // Only a bowl travelling towards her counts; one leaving her body passes.
        let toward = Vector(-x, 108 - y)
        guard motion.velocity.x * toward.x + motion.velocity.y * toward.y > 0 else { return nil }
        return y > 160 ? .head : y < 50 ? .feet : .body
    }
    /// Returns true when she catches the bowl; otherwise it rebounds and she flinches.
    private func bowlHitsPet(_ zone: BowlHit, motion: inout BowlMotion) -> Bool {
        bowlHitCooldown = now + 0.5
        if zone == .body && motion.velocity.length < 650 {
            returnBowl(); say(.caughtBowl); return true
        }
        let center = position + Vector(0, 108 * scale), away = motion.position - center
        let n = away.length > 0.01 ? away * (1 / away.length) : Vector(0, 1)
        let along = motion.velocity.x * n.x + motion.velocity.y * n.y
        if along < 0 { motion.velocity = motion.velocity - n * (2 * along) }
        motion.velocity = motion.velocity * 0.6
        if zone == .head { motion.velocity.y = max(motion.velocity.y, 260) }
        motion.angularVelocity = -motion.angularVelocity
        motion.position = motion.position + n * (12 * scale)
        flinchKind = zone; flinchBase = position; velocity = .init(); reachingUp = false
        activity = .flinching; activityStart = now; activityEnd = now + (zone == .head ? 0.9 : zone == .feet ? 0.7 : 0.6)
        if zone == .head {
            scene.setEmotion(model.preferences.anger ? "💢" : "!"); say(.bonked)
            if model.preferences.anger { chaseBoost = max(chaseBoost, 1.25) }
        } else { scene.setEmotion("!"); say(.startled) }
        wake(for: activityEnd - now + 0.3)
        return false
    }
    private func kickBowl() {
        kickedThisChase = true
        let direction: Double = velocity.x < 0 ? -1 : 1
        bowlMotion = .init(position: bowlPosition, velocity: .init(direction * (480 + random() * 260), 360 + random() * 200))
        bowlHitCooldown = now + 0.8; activityEnd = max(activityEnd, now + 5)
        scene.setEmotion("💦"); say(.kicked); model.status = "糟糕，踢飞了"
        bowlView.renderingPaused = false; redrawBowl(); wake(for: activityEnd - now + 1)
    }
    /// A window shown while the session is locked or the display is asleep (for
    /// example at login) can get an SKView whose render loop never starts: it stays
    /// an undrawn gray rectangle. If she should be drawing, is visible, and no frame
    /// arrived for 3 s, re-attach both views so SpriteKit starts a fresh loop.
    private func watchRenderer() {
        if petView.renderingPaused || frameCount != lastFrameSeen.count || !panel.occlusionState.contains(.visible) {
            lastFrameSeen = (frameCount, now); return
        }
        guard now - lastFrameSeen.time > 3, now - lastRendererKick > 10 else { return }
        recoverRenderer()
    }
    func recoverRenderer() {
        lastRendererKick = now; lastFrameSeen = (frameCount, now); rendererKicks += 1
        for (window, view, content) in [(panel, petView, scene as SKScene), (bowlPanel, bowlView, bowlScene as SKScene)] {
            window.contentView = nil; window.contentView = view
            view.isPaused = true; view.isPaused = false
            view.presentScene(nil); view.presentScene(content)
            view.needsDisplay = true
        }
        wake(for: 0.5)
    }
    // MARK: Everyday companionship (0.1.14)
    private func companionTick(mouse: Vector) {
        let p = model.preferences
        if now - lastIdleCheck >= 1 {
            let elapsed = min(5, now - lastIdleCheck); lastIdleCheck = now; userIdle = idleSource()
            if breakClock.tick(elapsed: elapsed, idle: userIdle, intervalMinutes: p.breakMinutes) { breakDue = true }
        }
        if p.aiCompanion && now - lastAgentCheck >= 10 {
            lastAgentCheck = now
            if let event = agents.sample(time: now, cpuPercent: agentSource?() ?? agentCPU.sample(now: now)) { agentEvent = event }
        }
        if p.perchOnWindows, let perch, dragging == nil, now - lastPerchCheck >= 0.5 { lastPerchCheck = now; checkPerch(perch) }
        if case .dozing = activity {
            if userIdle < 1.5 { wakeFromDoze() }
            else if now >= nextBreath && !reducedMotion { breathStart = now; nextBreath = now + 7; updateFrameBudget(); wake(for: 2.5) }
            return
        }
        guard case .idle = activity, dragging == nil, !cardOpen, gazeDemoUntil <= now else { return }
        let night = p.dailyRhythm && DayPart(hour: Calendar.current.component(.hour, from: Date())) == .lateNight
        // Doze off while the user is away; sooner late at night.
        if p.napMinutes > 0 && userIdle >= Double(p.napMinutes * 60) * (night ? 0.5 : 1) { startDoze(); return }
        if breakDue && userIdle < 60 { breakDue = false; remindBreak(); return }
        if let event = agentEvent, userIdle < 120 { agentEvent = nil; agentReact(event); return }
        if p.petting && scene.sootLevel == 0 && now > pettingCooldown {
            let local = Vector((mouse.x - panel.frame.minX) / scale, (mouse.y - panel.frame.minY) / scale)
            if petting.add(time: now, x: local.x, overHead: local.y > 140 && local.y < 216 && abs(local.x - 128) < 62) { beingPetted(); return }
        }
        if p.dailyRhythm && now - lastRhythmCheck >= 30 { lastRhythmCheck = now; rhythmTick(night: night) }
        // Standing on a window for a while, she sits on its top edge and swings her legs.
        if p.sitOnWindows, perch != nil, !lastHover, !reducedMotion, assets.clips["sitting"] != nil, now - idleSince >= sitAfter { startSitting(); return }
        // Wander off on her own once the user has paused typing and pointing for a moment.
        if p.wanderLevel > 0, now >= nextWander, userIdle >= 8, !fullscreen, !model.quiet, !lastHover, !reducedMotion, assets.clips["walking"] != nil { startWander() }
    }
    private func scheduleWander() {
        let range: ClosedRange<Double> = [0: 120.0...240, 1: 240...480, 2: 120...240, 3: 45...90][model.preferences.wanderLevel] ?? 120...240
        nextWander = now + range.lowerBound + (range.upperBound - range.lowerBound) * random()
    }
    func startWander() {
        scheduleWander()
        let p = model.preferences
        let surface: ClosedRange<Double>
        if let perch { surface = max(bounds.minX, perch.frame.minX + 24)...max(bounds.minX, min(bounds.maxX, perch.frame.maxX - 24)) }
        else { surface = bounds.minX...bounds.maxX }
        let icons = p.dockPeek ? (iconSource?() ?? DockIcons.read(now: now)) : []
        var plan = WanderPlanner.plan(feetX: position.x, surface: surface, onFloor: perch == nil, floorY: bounds.minY,
                                      windows: windowList().filter { $0.id != perch?.id }, icons: icons,
                                      allowClimb: p.climbWindows && assets.clips["climbing"] != nil, standOff: climbStandOff * scale, random: random)
        if let climb = plan.climb, climb.top > bounds.maxY { plan.climb = nil; plan.lookAt = CGPoint(x: climb.wallX, y: climb.top) }
        guard abs(plan.stopX - position.x) > 8 || plan.climb != nil || plan.lookAt != nil else { return }
        finishActivity(); scheduleWander()
        activity = .wandering; wanderPlan = plan; wanderPhase = .walking; wanderPhaseStart = now; walkClock = 0
        model.status = "出去走走"; wake(for: 0.3)
    }
    private func wanderStep(dt: Double) {
        guard let plan = wanderPlan else { finishActivity(); return }
        switch wanderPhase {
        case .walking:
            let dx = plan.stopX - position.x, step = 60 * scale * dt
            if abs(dx) > step {
                position.x += dx > 0 ? step : -step
                let name = dx < 0 ? "walking-left" : "walking-right"
                if scene.useGaze || scene.clip != name { scene.play(name, loop: true) }
                walkClock += dt; scene.frameOverride = Int(walkClock * 8) % 8
                return
            }
            position.x = plan.stopX
            if let climb = plan.climb {
                wanderPhase = .climbing; wanderPhaseStart = now; lastPerchCheck = now
                scene.play(climb.facingRight ? "climbing-right" : "climbing-left", loop: true); model.status = "爬窗户"
            } else if plan.lookAt != nil {
                wanderPhase = .looking; wanderPhaseStart = now; scene.useGaze = true; scene.frameOverride = nil
                switch plan.target {
                case .icon(let name) where model.preferences.speechEnabled: speechCue = nil; literalSpeech = BubbleText.clean("这是「\(name.prefix(10))」吗？"); refreshSpeech()
                case .window: say(.curious)
                default: break
                }
                scene.setEmotion("👀")
            } else { finishActivity() }
        case .climbing:
            guard let climb = plan.climb else { finishActivity(); return }
            scene.frameOverride = Int((now - wanderPhaseStart) * 3) % 4
            position.y += 45 * scale * dt
            if now - lastPerchCheck >= 0.5 {
                lastPerchCheck = now
                guard let window = windowList().first(where: { $0.id == climb.windowID }), abs(window.frame.maxY - climb.top) < 2 else {
                    // The window moved away mid-climb: she drops.
                    scene.useGaze = true; scene.frameOverride = nil; fallWindows = windowList(); fallSpeed = 0
                    activity = .falling; activityStart = now; scene.setEmotion("!"); model.status = "窗户跑掉啦"; wake(for: 3); return
                }
            }
            // Hands reach the top edge: pull herself up and stand on the window.
            if position.y + 190 * scale >= climb.top {
                position = Vector(climb.wallX + (climb.facingRight ? 40 : -40) * scale, climb.top)
                perch = windowList().first { $0.id == climb.windowID }; finishActivity(); savePosition()
                say(.climbed); emotionUntil = now + 2.5
            }
        case .looking:
            guard let target = plan.lookAt else { finishActivity(); return }
            let direction = gaze.update(dx: target.x - position.x, dy: target.y - (position.y + 110 * scale), overBody: false)
            if direction != gazeFollower.target { gazeFollower.aim(at: direction, immediately: reducedMotion) }
            gazeFollower.advance(dt: dt); scene.look = gazeFollower.direction
            if now - wanderPhaseStart > 3.5 { finishActivity(); emotionUntil = now + 1 }
        }
    }
    private func startSitting() {
        finishActivity(); activity = .sitting; activityStart = now; activityEnd = now + 45
        scene.play("sitting"); scene.frameOverride = 0; model.status = "坐在窗口边上"
        bowlPosition = restBowl(); placeWindows(); wake(for: 0.5)
    }
    /// Crouch, sit, then the lower legs swing one at a time; driven from the 10 Hz pulse so the
    /// renderer can rest between poses.
    private func sitTick() {
        let elapsed = now - activityStart
        let pose = elapsed < 0.35 ? 0 : elapsed < 1.6 ? 1 : [1, 2, 1, 3][Int((elapsed - 1.6) / 0.6) % 4]
        if scene.frameOverride != pose { scene.frameOverride = pose; wake(for: 0.1) }
        if now >= activityEnd { finishActivity(); idleSince = now + 40 }   // stand up; sit again a minute later
    }
    private func startDoze() {
        finishActivity(); activity = .dozing; dozeStart = now
        scene.useGaze = true; scene.look = 0; gazeFollower.aim(at: 0, immediately: true); scene.faceReaction = 3
        // Keep drawing until she has knelt and lain down (about one second).
        scene.setEmotion("💤"); model.status = "打了个小盹"; nextBreath = now + 2; wake(for: 1.2)
    }
    private func wakeFromDoze() {
        let long = now - dozeStart > 60, lying = scene.clip == "sleeping" && !scene.useGaze
        finishActivity()
        if lying {   // back up onto her knees for a moment before standing
            activity = .recovering; activityStart = now; activityEnd = now + 0.35
            scene.play("sleeping"); scene.frameOverride = 0; welcomeAfterRecovery = long; wake(for: 0.5); return
        }
        if long { welcome() }
    }
    private func welcome() {
        if model.preferences.wave && !reducedMotion { exerciseWave() }
        say(.welcomeBack); if case .idle = activity { emotionUntil = now + 3 }
    }
    private func remindBreak() {
        startStory(.begging, manual: true)
        if case .story = activity { activityEnd = now + 6; wake(for: 6.5) } else { emotionUntil = now + 6 }
        say(.breakTime); model.status = "该休息一下啦"
    }
    private func agentReact(_ event: AgentActivity.Event) {
        switch event {
        case .started: say(.aiWorking); emotionUntil = now + 4; model.status = "陪你等 AI 干活"; wake(for: 0.3)
        case .finished:
            if model.preferences.wave && !reducedMotion { exerciseWave() }
            say(.aiDone); if case .idle = activity { emotionUntil = now + 4 }
        }
    }
    private func beingPetted() {
        pettingCooldown = now + 8
        scene.faceReaction = 1; scene.setEmotion("♡"); say(.petted); emotionUntil = now + 2.5; wake(for: 0.3)
    }
    private func rhythmTick(night: Bool) {
        guard userIdle < 30 else { return }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        if DayPart(hour: Calendar.current.component(.hour, from: Date())) == .morning && greetedDay != day {
            greetedDay = day
            if model.preferences.wave && !reducedMotion { exerciseWave() }
            say(.morning); return
        }
        if night && now - lastNightNote > 3600 {
            lastNightNote = now; say(.lateNight); scene.setEmotion("🌙"); emotionUntil = now + 5; wake(for: 0.3)
        }
    }
    private func quotaMoodStory() -> Story? {
        let p = model.preferences
        guard p.quotaMood, let fraction = BowlQuotaReading.make(preferences: p, snapshot: quotaProviders[p.bowlQuotaSource]?.snapshot)?.fraction else { return nil }
        if fraction * 100 < p.lowQuotaThreshold, p.begging, random() < 0.6 { return .begging }
        if fraction > 0.8, p.eating, random() < 0.3 { return .eating }
        return nil
    }
    private func windowList() -> [WindowLedge.Window] {
        if let windowSource { return windowSource() }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0, own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { item in
            guard (item[kCGWindowOwnerPID as String] as? Int32) != own, (item[kCGWindowLayer as String] as? Int) == 0,
                  (item[kCGWindowAlpha as String] as? Double ?? 1) > 0.1, let id = item[kCGWindowNumber as String] as? Int,
                  let bounds = item[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width >= 200, rect.height >= 80 else { return nil }
            return (id, CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height))
        }
    }
    /// Dropped (or jumped) with her feet near a window's top edge: stand on it.
    private func tryPerch() {
        guard model.preferences.perchOnWindows,
              let ledge = WindowLedge.under(feetX: position.x, feetY: position.y, windows: windowList()),
              ledge.frame.maxY <= bounds.maxY, ledge.frame.maxY >= bounds.minY else { perch = nil; return }
        position.y = ledge.frame.maxY; perch = ledge; placeWindows()
    }
    private func checkPerch(_ ledge: WindowLedge.Window) {
        // She walked, jumped or was carried away by herself.
        guard abs(position.y - ledge.frame.maxY) < 1.5 else { perch = nil; return }
        if let current = windowList().first(where: { $0.id == ledge.id }),
           abs(current.frame.maxY - ledge.frame.maxY) < 2, abs(current.frame.minX - ledge.frame.minX) < 2 { return }
        perch = nil
        switch activity { case .chasing, .jumping, .draggingBody, .falling, .flinching, .hanging: return; default: break }
        finishActivity()
        fallWindows = windowList(); fallSpeed = 0; activity = .falling; activityStart = now
        scene.setEmotion("!"); model.status = "窗户跑掉啦"; wake(for: 3)
        if reducedMotion { position.y = WindowLedge.landing(feetX: position.x, fromY: position.y, toY: bounds.minY, windows: fallWindows).map { Double($0.frame.maxY) } ?? bounds.minY; land(on: nil) }
    }
    private func land(on ledge: WindowLedge.Window?) {
        perch = ledge ?? WindowLedge.under(feetX: position.x, feetY: position.y, windows: fallWindows); savePosition()
        flinchKind = .head; flinchBase = position; velocity = .init(); afterFlinchCue = .fell
        activity = .flinching; activityStart = now; activityEnd = now + 0.6
        scene.setEmotion("💫"); say(.fell); wake(for: 0.9)
    }
    /// Let go with a window top between her chest and just above her head: she grabs it and hangs.
    private func tryHang() {
        guard model.preferences.hangOnWindows, !reducedMotion, assets.clips["hanging"] != nil,
              let ledge = WindowLedge.grip(feetX: position.x, feetY: position.y, reach: (120 * scale)...(250 * scale), windows: windowList()) else { return }
        let y = ledge.frame.maxY - gripHeight * scale
        guard y >= bounds.minY, y <= bounds.maxY else { return }
        position.y = y; hangEdge = ledge; lastPerchCheck = now
        activity = .hanging; activityStart = now; activityEnd = now + 4.5
        scene.play("hanging", loop: true); scene.setEmotion("💦"); say(.hanging); model.status = "挂在窗口边上"
        bowlPosition = restBowl(); redrawBowl(); placeWindows(); wake(for: 4.7)
    }
    private func letGo() {
        hangEdge = nil; scene.useGaze = true; scene.look = 0; scene.frameOverride = nil
        fallWindows = windowList(); fallSpeed = 0; activity = .falling; activityStart = now
        scene.setEmotion("!"); model.status = "手酸了，松手"; wake(for: 3)
    }
    func canFeed() -> Bool { model.preferences.feeding && !model.paused && !inactive && dragging == nil && !cardOpen }
    /// Something dragged into her bowl. Only its kind and name are used; nothing is read or kept.
    func feed(_ food: Food) {
        guard canFeed() else { return }
        startStory(.eating, manual: true)
        let line: String
        switch food {
        case .text(let text): let bite = BubbleText.clean(text).prefix(8); line = bite.isEmpty ? "" : "「\(bite)」嚼嚼，好吃！"
        case .file(let name): line = "「\(name.prefix(8))」也能吃吗？嚼嚼"
        case .image: line = "这张图看起来好好吃！"
        case .link(let host): line = "\(host.prefix(12)) 味的白饭！"
        }
        if case .story = activity { activityEnd = now + 3.5; scene.play("steel-eating", duration: 3.5); eatingStartled = true; wake(for: 4) }
        if line.isEmpty || !model.preferences.speechEnabled { say(.fed) } else { speechCue = nil; literalSpeech = BubbleText.clean(line); refreshSpeech() }
        model.status = "谢谢投喂"
    }
    func jumpToPointer() { jump(to: pointer()) }
    private func jump(to target: Vector) {
        guard dragging == nil, !inactive, !model.paused, !cardOpen else { return }
        finishActivity(); jumpStart = position; jumpEnd = bounds.clamp(target); activity = .jumping
        activityStart = now; activityEnd = now + 0.84; scene.play("jumping"); wake(for: 1)
    }
    func celebrate() { if case .surprised = activity { return }; guard model.preferences.celebration && !model.paused && !model.quiet && !cardOpen else { return }; activity = .waving; activityEnd = now + model.preferences.celebrationDuration; scene.play("waving", loop: true); scene.setEmotion("✨"); wake(for: model.preferences.celebrationDuration + 0.2) }
    func mouseDown(_ target: PetView.Target, event: NSEvent) {
        if model.paused { if target == .body { showQuota?() }; return }
        if target == .bowl && !model.preferences.steal { return }
        dragging = target; pressPoint = location(of: event); pressPosition = position; didDrag = false
        bodyDragSampleTime = now; bodyDragLastMovement = -Double.infinity; bodyDragSpeed = 0
        let local = CGPoint(x: (pressPoint.x - panel.frame.minX) / scale, y: (pressPoint.y - panel.frame.minY) / scale)
        wiping = target == .body && scene.sootLevel > 0 && scene.faceContains(local)
        lastWipe = pressPoint
        throwSampler = ThrowSampler(); throwSampler.add(time: now, position: pressPoint)
    }
    func mouseDragged(_ target: PetView.Target, event: NSEvent) {
        guard dragging == target else { return }
        let mouse = location(of: event)
        guard (mouse - pressPoint).length > 4 || didDrag else { return }
        if wiping {
            if !didDrag { finishActivity(); scene.look = 0; scene.faceReaction = 2 }
            didDrag = true; scene.sootLevel = max(0, scene.sootLevel - (mouse - lastWipe).length / (150 * scale))
            lastWipe = mouse; say(scene.sootLevel > 0 ? .wiping : .clean)
            if scene.sootLevel == 0 { scene.setEmotion("♡"); scene.faceReaction = 1; emotionUntil = now + 2 }
            wake(for: 0.3); return
        }
        // A drag gesture never doubles as a click, even when moving is switched off.
        if target == .body && !model.preferences.draggable { didDrag = true; return }
        if !didDrag {
            if target == .body { finishActivity(); runPhase = 0; activity = .draggingBody }
            else {
                bowlDetached = true; bowlMotion = nil; bowlScene.bowl.alpha = 1; stealStart = now; beginChasing(); bowlView.renderingPaused = false
                // Taking her bowl three times within 90 seconds makes her properly cross.
                steals = steals.filter { now - $0 < 90 } + [now]
                if steals.count >= 3 && model.preferences.anger, case .chasing = activity { chaseBoost = 1.3; say(.furious); scene.setEmotion("💢") }
            }
        }
        didDrag = true
        if target == .body {
            let next = bounds.clamp(pressPosition + mouse - pressPoint), delta = next - position
            if delta.length > 0.1 {
                bodyDragSpeed = min(600, delta.length / max(1.0 / 120, now - bodyDragSampleTime) / scale)
                bodyDragLastMovement = now
                if delta.x < -0.5 { bodyDragFacingLeft = true } else if delta.x > 0.5 { bodyDragFacingLeft = false }
            }
            bodyDragSampleTime = now; position = next
            updateBodyDragPose(dt: 0); updateFrameBudget()
        }
        if target == .bowl { bowlPosition = mouse; throwSampler.add(time: now, position: mouse) }
        placeWindows(); wake(for: 0.3)
    }
    func mouseUp(_ target: PetView.Target, event: NSEvent) {
        guard dragging == target else { return }
        dragging = nil
        if wiping && didDrag { wiping = false; scene.faceReaction = scene.sootLevel == 0 ? 1 : 0; emotionUntil = now + 2; wake(for: 0.4); return }
        wiping = false
        if target == .body { if didDrag { finishActivity(); tryPerch(); if perch == nil { tryHang() }; savePosition() } else {
            if model.preferences.touch { scene.setEmotion("♡"); wake(for: 0.25)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.showQuota?() }
            } else { showQuota?() }
        } }
        else if didDrag {
            throwSampler.add(time: now, position: location(of: event))
            let speed = throwSampler.velocity()
            if (bowlPosition - heldBowl()).length < 80 * scale && speed.length < 300 { returnBowl() }
            else { bowlMotion = .init(position: bowlPosition, velocity: model.preferences.throwing ? speed : .init()); bowlHitCooldown = now + 0.35; beginChasing() }
        }
    }
    private func updateBodyDragPose(dt: Double) {
        if bodyDragAnimating {
            let name = bodyDragFacingLeft ? "running-left" : "running-right"
            if scene.useGaze || scene.clip != name { scene.play(name, duration: 0.8, loop: true) }
            runPhase += dt * min(1.8, max(0.35, bodyDragSpeed / 145))
            if let count = assets.clips["jog"]?.frames { scene.frameOverride = Int(runPhase / 0.8 * Double(count)) % count }
            wake(for: 0.2)
        } else if !scene.useGaze {
            scene.useGaze = true; scene.look = 0; scene.frameOverride = nil; updateFrameBudget(); wake(for: 0.2)
        }
    }
    private func location(of event: NSEvent) -> Vector {
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        return Vector(point.x, point.y)
    }
    func pauseChanged(_ paused: Bool) {
        if paused { finishActivity(); dragging = nil; petView.renderingPaused = true; bowlView.renderingPaused = true }
        else { scene.suspended = false; wake(for: 0.5); scheduleAmbient() }
    }
    func updateVisibility() {
        if inactive { dragging = nil; wiping = false; timer?.invalidate(); timer = nil; panel.orderOut(nil); bowlPanel.orderOut(nil); petView.renderingPaused = true; bowlView.renderingPaused = true }
        else { startPulse(); panel.orderFrontRegardless(); if bowlVisible { bowlPanel.orderFrontRegardless() }; wake(for: 0.2) }
    }
    private func detectFullscreen() {
        let display = currentScreen.frame
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        fullscreen = windows.contains { item in
            guard (item[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  (item[kCGWindowLayer as String] as? Int) == 0,
                  let dictionary = item[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return false }
            // Core Graphics uses a top-left origin; width/height and display overlap
            // are enough here after translating relative to the primary screen.
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? display.maxY
            let cocoa = CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
            return cocoa.intersection(display).width >= display.width - 2 && cocoa.intersection(display).height >= display.height - 2
        }
        updateVisibility()
    }
    func showMenu(event: NSEvent, view: NSView) {
        let menu = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) {
            let item = ActionMenuItem(title, action: action); menu.addItem(item)
        }
        add("查看额度") { [weak self] in self?.showQuota?() }
        add("设置…") { [weak self] in self?.showSettings?() }
        add("预览 32 向注视") { [weak self] in self?.exerciseGaze(seconds: 12) }
        menu.addItem(.separator())
        for story in Story.allCases { add(story.title) { [weak self] in self?.startStory(story, manual: true) } }
        menu.addItem(.separator())
        add(model.quiet ? "恢复自然陪伴" : "安静陪伴") { [weak self] in self?.model.quiet.toggle() }
        add(model.paused ? "继续互动" : "暂停互动") { [weak self] in self?.model.paused.toggle() }
        add("移回屏幕角落") { [weak self] in self?.resetPosition() }
        add("退出大肥鱼") { NSApp.terminate(nil) }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
    func stop() { timer?.invalidate(); if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }; model.save() }
    func exerciseGaze(seconds: Double = 18, soot: Bool = false, upperLeftOnly: Bool = false) {
        guard !model.paused, !inactive else { return }
        finishActivity(); if soot { scene.sootLevel = 1; say(.wipeRequest) }
        gazeDemoUpperLeftOnly = upperLeftOnly
        gazeDemoStart = now; gazeDemoUntil = now + seconds
        updateFrameBudget(); wake(for: seconds + 0.3)
    }
    func exerciseThrow(from offset: Vector? = nil, velocity: Vector = .init(-850, 700), hitCooldown: Double = 0.35) {
        guard !model.paused, !inactive else { return }
        bowlVisible = true; bowlDetached = true; bowlPosition = offset.map { position + $0 * scale } ?? heldBowl()
        bowlMotion = .init(position: bowlPosition, velocity: velocity); bowlHitCooldown = now + hitCooldown
        bowlPanel.orderFrontRegardless(); bowlView.renderingPaused = false; beginChasing()
    }
    /// Diagnostics: the same pour and delight as a real quota reset, from `from` to the current reading.
    func exerciseRefill(from: Double = 0.06) { guard !model.paused, !inactive else { return }; refilled(from: from) }
    /// Diagnostics: a scripted body drag through the normal mouse handlers, released with the
    /// frontmost window's top edge `below` points above her feet.
    func exerciseHang(below: Double = 180) {
        guard !model.paused, !inactive, let ledge = windowList().first else { return }
        finishActivity()
        let grab = position + Vector(0, 110 * scale)
        let drop = Vector(ledge.frame.midX, ledge.frame.maxY - below * scale) + Vector(0, 110 * scale)
        func event(_ type: NSEvent.EventType, _ p: Vector) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: p.x, y: p.y), modifierFlags: [], timestamp: now, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        if let down = event(.leftMouseDown, grab) { mouseDown(.body, event: down) }
        for step in 1...30 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) / 60) { MainActor.assumeIsolated { [weak self] in
                guard let self, let e = event(step == 30 ? .leftMouseUp : .leftMouseDragged, grab + (drop - grab) * (Double(step) / 30)) else { return }
                if step == 30 { self.mouseUp(.body, event: e) } else { self.mouseDragged(.body, event: e) }
            } }
        }
    }
    /// Diagnostics: wander right now, as if the timer had fired and the user were away.
    func exerciseWander(climb: Bool = false) {
        let real = random, source = windowSource
        if climb {   // offer only windows standing on the floor, and roll low enough to climb the first
            let floorY = bounds.minY, all = windowList()
            random = { 0.1 }; windowSource = { all.filter { $0.frame.minY <= floorY + 60 } }
        }
        userIdle = 30; startWander(); random = real; windowSource = source
    }
    /// Diagnostics: dropped onto the frontmost window's top, she sits down a second later.
    func exerciseSit() { sitAfter = 1; exerciseHang(below: -10) }
    /// Diagnostics: pretends the user has been away for a while, then comes back after `seconds`.
    func exerciseDoze(seconds: Double = 9) {
        let real = idleSource; idleSource = { 4000 }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { [weak self] in self?.idleSource = real } }
    }
    var isHanging: Bool { if case .hanging = activity { return true }; return false }
    var isSurprised: Bool { if case .surprised = activity { return true }; return false }
    var isWandering: Bool { if case .wandering = activity { return true }; return false }
    var isSitting: Bool { if case .sitting = activity { return true }; return false }
    var isLyingDown: Bool { if case .dozing = activity { return scene.clip == "sleeping" && !scene.useGaze }; return false }
    func exerciseWave() {
        guard !model.paused, !inactive else { return }
        finishActivity(); activity = .waving; activityStart = now; activityEnd = now + 2.6
        scene.play("waving", duration: 2.6); wake(for: 2.7)
    }
    /// Diagnostics only: replays one body drag through the normal mouse handlers
    /// (jitter, right, hold, left, vertical, hold, edge, release). Real cursor hit
    /// testing is not covered; each tick is logged for frame-by-frame review.
    func exerciseBodyDrag(log folder: URL?) {
        guard !model.paused, !inactive else { return }
        finishActivity()
        let keys: [(Double, Vector)] = [(0, .init()), (0.4, .init(3, 1)), (0.8, .init()), (2.4, .init(300, 0)), (3.6, .init(300, 0)),
                                        (4.4, .init(-150, 0)), (5.4, .init(-150, 150)), (6.6, .init(-150, 150)), (7.4, .init(2400, 150)), (8.6, .init(2400, 150))]
        let press = Vector(panel.frame.midX, panel.frame.minY + 140 * scale), began = now, end = keys[keys.count - 1].0
        var file: FileHandle?
        if let folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("drag-preview-\(ProcessInfo.processInfo.processIdentifier).jsonl")
            FileManager.default.createFile(atPath: url.path, contents: nil); file = try? FileHandle(forWritingTo: url)
        }
        func send(_ type: NSEvent.EventType, _ t: Double) {
            let i = keys.lastIndex { $0.0 <= t } ?? 0, j = min(keys.count - 1, i + 1)
            let f = keys[j].0 > keys[i].0 ? (t - keys[i].0) / (keys[j].0 - keys[i].0) : 0
            let p = press + keys[i].1 + (keys[j].1 - keys[i].1) * min(1, f)
            guard let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: p.x, y: p.y), modifierFlags: [], timestamp: now, windowNumber: 0,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            switch type { case .leftMouseDown: mouseDown(.body, event: event); case .leftMouseUp: mouseUp(.body, event: event); default: mouseDragged(.body, event: event) }
            let row: [String: Any] = ["t": t, "type": type == .leftMouseDragged ? "drag" : type == .leftMouseDown ? "down" : "up", "pointerX": p.x, "pointerY": p.y,
                                      "petX": position.x, "petY": position.y, "bowlX": bowlPosition.x, "bowlY": bowlPosition.y, "clip": scene.clip,
                                      "running": !scene.useGaze, "frame": scene.frameOverride ?? -1, "fps": petView.preferredFramesPerSecond, "frameCount": frameCount]
            if var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) { data.append(10); try? file?.write(contentsOf: data) }
        }
        send(.leftMouseDown, 0)
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = self.now - began
                if t >= end { send(.leftMouseUp, t); timer.invalidate(); try? file?.close() } else { send(.leftMouseDragged, t) }
            }
        }
    }
    /// Diagnostics only: steal-and-hold (snatch), head hit, slow catch, feet hit, then a forced kick.
    func exerciseBowlPlay() {
        guard !model.paused, !inactive else { return }
        func event(_ type: NSEvent.EventType, _ p: Vector) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: p.x, y: p.y), modifierFlags: [], timestamp: now, windowNumber: 0,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        func at(_ delay: Double, _ action: @escaping @MainActor () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { action() } }
        }
        finishActivity()
        let grab = bowlPosition, hold = grab + Vector(260 * scale, 0)
        if let down = event(.leftMouseDown, grab) { mouseDown(.bowl, event: down) }
        for step in 1...18 { at(Double(step) / 60) { [weak self] in
            guard let self, let e = event(.leftMouseDragged, grab + (hold - grab) * (Double(step) / 18)) else { return }; self.mouseDragged(.bowl, event: e) } }
        for tick in 0..<200 { at(0.3 + Double(tick) / 60) { [weak self] in   // keep holding still; real AppKit sends no events, this mirrors a jitter-free hand
            guard let self, self.dragging == .bowl, let e = event(.leftMouseDragged, hold) else { return }; self.mouseDragged(.bowl, event: e) } }
        at(4.5) { [weak self] in if let self, self.dragging == .bowl, let e = event(.leftMouseUp, hold) { self.mouseUp(.bowl, event: e) } }
        at(7) { [weak self] in self?.finishActivity(); self?.exerciseThrow(from: Vector(0, 300), velocity: Vector(0, -900), hitCooldown: 0) }
        at(14) { [weak self] in self?.finishActivity(); self?.exerciseThrow(from: Vector(-170, 110), velocity: Vector(420, 60), hitCooldown: 0) }
        at(18) { [weak self] in self?.finishActivity(); self?.exerciseThrow(from: Vector(-150, 20), velocity: Vector(900, 0), hitCooldown: 0) }
        at(24) { [weak self] in
            guard let self else { return }
            let saved = self.random; self.random = { 0 }; self.finishActivity()
            self.exerciseThrow(from: Vector(260, 0), velocity: Vector(30, -10), hitCooldown: 0)
            at(12) { [weak self] in self?.random = saved }
        }
    }
    var screenFrame: NSRect { currentScreen.visibleFrame }
    var characterFrame: NSRect { panel.frame }
}

@MainActor final class ActionMenuItem: NSMenuItem {
    let handler: () -> Void
    init(_ title: String, action: @escaping () -> Void) { handler = action; super.init(title: title, action: #selector(invoke), keyEquivalent: ""); target = self }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}
