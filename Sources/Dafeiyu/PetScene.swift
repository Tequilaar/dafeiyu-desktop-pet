import AppKit
import SpriteKit
import DafeiyuCore

@MainActor final class PetScene: SKScene {
    let body = SKSpriteNode()
    let gazeEyes = SKSpriteNode()
    private let emotion = SKLabelNode(fontNamed: "AppleColorEmoji")
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 82, height: 10))
    private let assets: AssetStore
    var onFrame: ((TimeInterval) -> Void)?
    var clip = "idle"
    var clipStarted = 0.0
    var clipDuration = 0.0
    var loop = false
    var look = 0
    var blink = 0
    var useGaze = true
    var suspended = false
    var frameOverride: Int?
    var emotionStrength = 0.35
    private var tearDrops: [SKShapeNode] = []
    private let soot = SKNode()
    private let bubble = SKLabelNode(fontNamed: "PingFangSC-Medium")
    private let bubbleBackground = SKShapeNode()
    private let bubbleTail = SKShapeNode()
    private var speech = ""
    var faceReaction = 0
    var sootLevel = 0.0 { didSet { soot.alpha = sootLevel } }
    private var displayedKey = ""
    private(set) var renderedGazeDirections = Set<Int>()
    init(assets: AssetStore) {
        self.assets = assets
        super.init(size: CGSize(width: 256, height: 288))
        scaleMode = .aspectFit; backgroundColor = .clear
        shadow.fillColor = NSColor.black.withAlphaComponent(0.13); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 128, y: 5); addChild(shadow)
        body.anchorPoint = CGPoint(x: 0.5, y: 0); body.position = CGPoint(x: 128, y: 0)
        body.size = CGSize(width: 192, height: 208); addChild(body)
        let eyeRect = assets.gazeLayout.eyeRect.map { CGFloat($0) }
        gazeEyes.size = CGSize(width: eyeRect[2], height: eyeRect[3])
        gazeEyes.position = CGPoint(x: eyeRect[0] + eyeRect[2] / 2 - 128, y: 208 - eyeRect[1] - eyeRect[3] / 2)
        gazeEyes.zPosition = 0.1; gazeEyes.isHidden = true; body.addChild(gazeEyes)
        emotion.fontSize = 24; emotion.position = CGPoint(x: 205, y: 167); emotion.zPosition = 5; addChild(emotion)
        soot.zPosition = 7; soot.alpha = 0; addChild(soot)
        for (x, y, w, h, angle) in [(-15.0, 0.0, 12.0, 5.0, 0.2), (14.0, -1.0, 10.0, 6.0, -0.3), (0.0, 16.0, 9.0, 4.0, -0.4)] {
            let mark = SKShapeNode(ellipseOf: CGSize(width: w, height: h))
            mark.fillColor = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 0.78); mark.strokeColor = .clear
            mark.position = CGPoint(x: x, y: y); mark.zRotation = angle; soot.addChild(mark)
        }
        let speechColor = NSColor(calibratedRed: 0.94, green: 0.97, blue: 1, alpha: 0.98)
        bubbleBackground.fillColor = speechColor; bubbleBackground.strokeColor = NSColor.systemBlue.withAlphaComponent(0.35)
        bubbleBackground.lineWidth = 0.8; bubbleBackground.position = CGPoint(x: 128, y: 232)
        bubbleBackground.zPosition = 8; bubbleBackground.isHidden = true; addChild(bubbleBackground)
        let tail = CGMutablePath(); tail.move(to: CGPoint(x: -5, y: 0)); tail.addLine(to: CGPoint(x: 5, y: 0)); tail.addLine(to: CGPoint(x: 0, y: -7)); tail.closeSubpath()
        bubbleTail.path = tail; bubbleTail.fillColor = speechColor; bubbleTail.strokeColor = .clear
        bubbleTail.position = CGPoint(x: 128, y: 218); bubbleTail.zPosition = 8; bubbleTail.isHidden = true; addChild(bubbleTail)
        bubble.fontSize = 13; bubble.fontColor = NSColor(calibratedRed: 0.12, green: 0.2, blue: 0.32, alpha: 1)
        bubble.numberOfLines = 2; bubble.preferredMaxLayoutWidth = 208; bubble.verticalAlignmentMode = .center
        bubble.position = CGPoint(x: 128, y: 227); bubble.zPosition = 9; addChild(bubble)
        for x in [113.0, 143.0] {
            let drop = SKShapeNode(ellipseOf: CGSize(width: 4, height: 7))
            drop.fillColor = NSColor.systemCyan.withAlphaComponent(0.8); drop.strokeColor = .clear
            drop.position = CGPoint(x: x, y: 133); drop.zPosition = 6; drop.isHidden = true
            addChild(drop); tearDrops.append(drop)
        }
        refresh(now: ProcessInfo.processInfo.systemUptime)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func update(_ currentTime: TimeInterval) {
        onFrame?(currentTime)
        if !suspended { refresh(now: ProcessInfo.processInfo.systemUptime) }
    }
    func play(_ name: String, duration: Double? = nil, loop: Bool = false) {
        clip = name; clipStarted = ProcessInfo.processInfo.systemUptime
        clipDuration = duration ?? (assets.clips[name]?.durationMs ?? 1200) / 1000
        self.loop = loop; useGaze = false; frameOverride = nil; displayedKey = ""
    }
    func refresh(now: Double) {
        let name: String
        let frame: Int
        if useGaze { name = "look-\(max(blink, faceReaction))"; frame = (look % GazeSelector.count + GazeSelector.count) % GazeSelector.count }
        else {
            name = atlas(for: clip)
            let count = assets.clips[name]?.frames ?? 1
            let elapsed = max(0, now - clipStarted)
            let fraction = loop ? elapsed.truncatingRemainder(dividingBy: max(0.1, clipDuration)) / max(0.1, clipDuration) : min(0.9999, elapsed / max(0.1, clipDuration))
            frame = min(count - 1, max(0, frameOverride ?? Int(fraction * Double(count))))
        }
        body.xScale = !useGaze && clip.hasSuffix("-left") && name != clip ? -1 : 1
        let key = "\(name):\(frame)"
        let side = useGaze ? sin(Double(look) / Double(GazeSelector.count) * 2 * .pi) : clip.contains("running") && clip != "steel-eating" ? (body.xScale < 0 ? -1.0 : 1.0) : 0
        let faceX: [Double] = [96,99,107,113,117,111,104,101,96,84,72,70,71,68,76,94]
        let cheekY: [Double] = [108,110,110,110,110,107,96,101,95,104,83,83,93,103,108,105]
        if useGaze {
            if assets.gazeFaces.count == GazeSelector.count {
                let face = assets.gazeFaces[frame]; soot.position = CGPoint(x: face.x, y: face.y)
            } else {
                let a = frame / 2, b = (a + 1) % 16, t = frame % 2 == 0 ? 0.0 : 0.5
                soot.position = CGPoint(x: 32 + faceX[a] * (1 - t) + faceX[b] * t, y: cheekY[a] * (1 - t) + cheekY[b] * t)
            }
        } else {
            soot.position = CGPoint(x: 128 + side * 16, y: name == "explosion-body" && frame >= 4 && frame <= 5 ? 94 : 110)
        }
        soot.xScale = 1 - abs(side) * 0.35
        guard key != displayedKey, let texture = assets.texture(useGaze ? "look-0" : name, frame: frame) else { return }
        displayedKey = key; body.texture = texture
        gazeEyes.isHidden = !useGaze || name == "look-0"
        gazeEyes.texture = gazeEyes.isHidden ? nil : assets.texture(name, frame: frame)
        if useGaze { renderedGazeDirections.insert(frame) }
        body.size = useGaze || name == "sleeping" ? CGSize(width: 256, height: 208) : name == "hanging" || name == "sitting" ? CGSize(width: 256, height: 288) : name == "climbing" ? CGSize(width: 192, height: 240) : CGSize(width: 192, height: 208)
        shadow.isHidden = !useGaze && ["hanging", "sitting", "climbing"].contains(name)   // no floor under her feet
        // Lying down her head is low and to the right; keep the 💤 beside it.
        emotion.position = !useGaze && name == "sleeping" && frame >= 1 ? CGPoint(x: 212, y: 122) : CGPoint(x: 205, y: 167)
    }
    func setEmotion(_ text: String) {
        emotion.text = text == "💧" ? "" : text
        emotion.alpha = emotionStrength == 0 ? 0 : 0.5 + emotionStrength * 0.5
        emotion.setScale(0.8 + emotionStrength * 0.4)
        for (index, drop) in tearDrops.enumerated() {
            drop.removeAllActions(); drop.isHidden = text != "💧" || emotionStrength == 0
            drop.position.y = 133; drop.alpha = 0.8
            if !drop.isHidden {
                let fall = SKAction.group([.moveBy(x: 0, y: -18 - emotionStrength * 12, duration: 1.2), .fadeOut(withDuration: 1.2)])
                drop.run(.repeatForever(.sequence([.wait(forDuration: Double(index) * 0.2), .run { drop.position.y = 133; drop.alpha = 0.8 }, fall, .wait(forDuration: 0.8)])))
            }
        }
    }
    func puff(strength: Double) {
        guard strength > 0 else { return }
        for index in 0..<Int(3 + strength * 5) {
            let cloud = SKShapeNode(circleOfRadius: 4 + strength * 5)
            cloud.fillColor = NSColor.white.withAlphaComponent(0.65); cloud.strokeColor = .clear
            cloud.position = CGPoint(x: 128, y: 90); cloud.zPosition = 3; addChild(cloud)
            let angle = Double(index) * 2.4
            cloud.run(.sequence([.group([.moveBy(x: cos(angle) * 42, y: 22 + abs(sin(angle)) * 35, duration: 0.5), .fadeOut(withDuration: 0.5), .scale(to: 1.8, duration: 0.5)]), .removeFromParent()]))
        }
    }
    /// Highest scene point the bubble may reach; lowered near the menu bar so the line stays readable.
    var bubbleCeiling: CGFloat = 288 { didSet { if abs(bubbleCeiling - oldValue) > 0.5 { layoutBubble() } } }
    func say(_ text: String) {
        guard speech != text else { return }; speech = text; bubble.text = text
        bubbleBackground.isHidden = text.isEmpty; bubbleTail.isHidden = text.isEmpty
        layoutBubble()
    }
    private func layoutBubble() {
        let width = min(230, max(60, bubble.frame.width + 22))
        // Normally above her head; under the menu bar it slides down over her hair, never her eyes.
        let height = min(60, max(30, bubble.frame.height + 14)), centerY = max(160 + height / 2, min(218 + height / 2, bubbleCeiling - height / 2))
        bubble.position.y = centerY; bubbleBackground.position.y = centerY; bubbleTail.position.y = centerY - height / 2
        bubbleBackground.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerWidth: 10, cornerHeight: 10, transform: nil)
    }
    func faceContains(_ point: CGPoint) -> Bool {
        abs(point.x - soot.position.x) < 39 && abs(point.y - soot.position.y) < 30
    }
    var activeAtlas: String { useGaze ? "look-\(max(blink, faceReaction))" : atlas(for: clip) }
    /// Directional clips share one right-facing atlas, mirrored for "-left".
    private func atlas(for clip: String) -> String {
        if clip.hasPrefix("running-") && assets.clips["jog"] != nil { return "jog" }
        for base in ["walking", "climbing"] where clip.hasPrefix(base + "-") { return base }
        return clip
    }
    func containsCharacter(_ point: CGPoint) -> Bool {
        // A narrow silhouette avoids an invisible rectangular desktop blocker.
        let dx = (point.x - 128) / 79, dy = (point.y - 108) / 103
        return dx * dx + dy * dy <= 1
    }
}

@MainActor final class BowlScene: SKScene {
    let bowl = SKNode()
    private let prop = SKSpriteNode()
    private let rice = SKCropNode()
    private let riceImage = SKSpriteNode()
    private let riceMask = SKShapeNode()
    private let badge = SKLabelNode(fontNamed: "PingFangSC-Medium")
    private let badgeBackground = SKShapeNode()
    private let filled: SKTexture?
    private let empty: SKTexture?
    private var quotaReading: BowlQuotaReading?
    private var showQuotaLabel = true
    private var storyRice: Bool?
    private(set) var displayedFraction: Double?
    private(set) var quotaIsDisplayed = false
    private var pour: (from: Double, start: Double, duration: Double)?
    var isPouring: Bool { pour != nil }
    init(assets: AssetStore) {
        filled = assets.texture("steel-props", frame: 0); empty = assets.texture("steel-props", frame: 1)
        super.init(size: CGSize(width: 128, height: 128)); backgroundColor = .clear; scaleMode = .aspectFit
        bowl.position = CGPoint(x: 64, y: 64); addChild(bowl)
        prop.texture = filled; prop.size = CGSize(width: 90, height: 67.5); bowl.addChild(prop)
        riceImage.texture = filled; riceImage.size = prop.size; rice.addChild(riceImage)
        riceMask.fillColor = .white; riceMask.strokeColor = .clear
        rice.maskNode = riceMask; rice.zPosition = 1; rice.isHidden = true; bowl.addChild(rice)
        badge.fontSize = 9; badge.fontColor = NSColor(calibratedRed: 0.12, green: 0.2, blue: 0.32, alpha: 1)
        badge.verticalAlignmentMode = .center; badge.position = CGPoint(x: 0, y: -36); badge.zPosition = 3
        badgeBackground.fillColor = NSColor(calibratedRed: 0.94, green: 0.97, blue: 1, alpha: 0.98)
        badgeBackground.strokeColor = NSColor.systemBlue.withAlphaComponent(0.25); badgeBackground.lineWidth = 0.5
        badgeBackground.position = badge.position; badgeBackground.zPosition = 2
        badge.isHidden = true; badgeBackground.isHidden = true
        bowl.addChild(badgeBackground); bowl.addChild(badge)
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @discardableResult func setQuota(_ reading: BowlQuotaReading?, showLabel: Bool) -> Bool {
        guard reading != quotaReading || showLabel != showQuotaLabel else { return false }
        quotaReading = reading; showQuotaLabel = showLabel
        if storyRice == nil { renderRice() }
        return storyRice == nil
    }
    func setRice(_ visible: Bool) { storyRice = visible; renderRice() }
    /// Quota reset: the rice rises from `from` to the current reading instead of jumping.
    func pourRice(from: Double, duration: Double) { pour = (from, ProcessInfo.processInfo.systemUptime, duration); renderRice() }
    override func update(_ currentTime: TimeInterval) { if pour != nil { renderRice() } }
    func resumeQuota() { storyRice = nil; renderRice() }
    private func renderRice() {
        quotaIsDisplayed = quotaReading != nil && storyRice == nil
        guard quotaIsDisplayed, let reading = quotaReading else {
            prop.texture = storyRice == false ? empty : filled; pour = nil
            rice.isHidden = true; badge.isHidden = true; badgeBackground.isHidden = true; displayedFraction = nil
            return
        }
        prop.texture = empty; displayedFraction = reading.fraction
        var fraction = reading.fraction ?? 0
        if let pour {
            let t = min(1, (ProcessInfo.processInfo.systemUptime - pour.start) / max(0.1, pour.duration))
            if t >= 1 { self.pour = nil } else { fraction = pour.from + (fraction - pour.from) * (1 - (1 - t) * (1 - t)) }
        }
        rice.isHidden = fraction <= 0
        // Reuse the existing painted grains. Lower them behind the front lip;
        // update this tiny mask only when the quota changes (or while rice pours in after a reset).
        let unit = 90.0 / 256, offset = (1 - sqrt(fraction)) * 21
        riceImage.position.y = -offset
        let outline: [[Double]] = [[39,84],[50,73],[70,65],[88,50],[112,36],[127,28],[145,34],[160,44],[175,55],[188,65],[205,77],[215,85],[191,89],[152,91],[110,91],[72,89]]
        let points = outline.map { CGPoint(x: ($0[0] - 128) * unit, y: (96 - $0[1]) * unit - offset) }
        var visible: [CGPoint] = []
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count], insideA = a.y >= 2, insideB = b.y >= 2
            if insideA { visible.append(a) }
            if insideA != insideB { let t = (2 - a.y) / (b.y - a.y); visible.append(CGPoint(x: a.x + (b.x - a.x) * t, y: 2)) }
        }
        let path = CGMutablePath(); if visible.count >= 3 { path.addLines(between: visible); path.closeSubpath() }
        riceMask.path = path
        badge.text = reading.label
        badge.fontColor = reading.stale ? .systemOrange : NSColor(calibratedRed: 0.12, green: 0.2, blue: 0.32, alpha: 1)
        badge.isHidden = !showQuotaLabel && reading.fraction != nil && !reading.stale
        badgeBackground.isHidden = badge.isHidden
        let width = min(116, max(48, badge.frame.width + 12))
        badgeBackground.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -8, width: width, height: 16), cornerWidth: 7, cornerHeight: 7, transform: nil)
    }
}

@MainActor final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Without this, AppKit moves a window that reaches under the menu bar back down by
    // itself, which split her from her bowl and stopped her ~90 pt below the top.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    init(size: NSSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; hidesOnDeactivate = false
        isReleasedWhenClosed = false; level = .floating; animationBehavior = .none
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
    }
}

@MainActor final class PetView: SKView, SKViewDelegate {
    enum Target { case body, bowl }
    let target: Target
    weak var owner: DesktopController?
    // Gate updates/renders through SpriteKit's delegate. Repeatedly pausing the
    // entire SKView can leave its display loop asleep after a popover on macOS.
    var renderingPaused = false {
        didSet { if oldValue && !renderingPaused { needsDisplay = true } }
    }
    init(frame: NSRect, target: Target) {
        self.target = target; super.init(frame: frame)
        allowsTransparency = true; ignoresSiblingOrder = true; preferredFramesPerSecond = 30
        shouldCullNonVisibleNodes = true; delegate = self
        if target == .bowl { registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff]) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    nonisolated func view(_ view: SKView, shouldRenderAtTime time: TimeInterval) -> Bool {
        MainActor.assumeIsolated { !renderingPaused }
    }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { owner?.mouseDown(target, event: event) }
    override func mouseDragged(with event: NSEvent) { owner?.mouseDragged(target, event: event) }
    override func mouseUp(with event: NSEvent) { owner?.mouseUp(target, event: event) }
    override func rightMouseDown(with event: NSEvent) { owner?.showMenu(event: event, view: self) }
    // Feeding: things dropped into the bowl. Copy semantics, so a dragged file is never moved.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { owner?.canFeed() == true ? .copy : [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { owner?.canFeed() == true ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let owner, owner.canFeed() else { return false }
        let board = sender.draggingPasteboard
        if let url = (board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first {
            if url.isFileURL {
                let image = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"].contains(url.pathExtension.lowercased())
                owner.feed(image ? .image : .file(url.deletingPathExtension().lastPathComponent))
            } else { owner.feed(.link(url.host ?? url.absoluteString)) }
        } else if let text = board.string(forType: .string) { owner.feed(.text(text)) }
        else if NSImage.canInit(with: board) { owner.feed(.image) }
        else { return false }
        return true
    }
}
