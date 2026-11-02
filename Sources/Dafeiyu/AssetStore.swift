import AppKit
import SpriteKit
import ImageIO
import DafeiyuCore

@MainActor final class AssetStore {
    struct Clip: Decodable { let frames: Int; let durationMs: Double; let width: Int; let height: Int; let columns: Int }
    let root: URL
    let clips: [String: Clip]
    struct FaceAnchor: Decodable { let x: Double; let y: Double }
    let gazeFaces: [FaceAnchor]
    struct GazeLayout: Decodable {
        let density: Int
        let bodyCell: [Int]
        let eyeCell: [Int]
        let eyeRect: [Int]
        let columns: Int
        let rows: Int
    }
    let gazeLayout: GazeLayout
    private var atlases: [String: SKTexture] = [:]
    private var frames: [String: [SKTexture]] = [:]
    private var access: [String: TimeInterval] = [:]
    private var cachedPortrait: NSImage?
    init() {
        root = Bundle.module.resourceURL!.appendingPathComponent("Assets")
        clips = (try? JSONDecoder().decode([String: Clip].self, from: Data(contentsOf: root.appendingPathComponent("clips.json")))) ?? [:]
        gazeFaces = (try? JSONDecoder().decode([FaceAnchor].self, from: Data(contentsOf: root.appendingPathComponent("gaze-faces.json")))) ?? []
        gazeLayout = try! JSONDecoder().decode(GazeLayout.self, from: Data(contentsOf: root.appendingPathComponent("gaze-layout.json")))
    }
    func texture(_ name: String, frame: Int = 0) -> SKTexture? {
        access[name] = ProcessInfo.processInfo.systemUptime
        if frames[name] == nil { load(name) }
        guard let list = frames[name], !list.isEmpty else { return nil }
        return list[max(0, frame) % list.count]
    }
    private func load(_ name: String) {
        guard let source = CGImageSourceCreateWithURL(root.appendingPathComponent(name + ".png") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let atlas = SKTexture(cgImage: image); atlas.filteringMode = .linear
        // Downscaled Retina artwork benefits from prefiltered levels, especially
        // during breathing and the smaller user-selected character sizes.
        atlas.usesMipmaps = name == "look-0" || !name.hasPrefix("look-")
        atlases[name] = atlas
        let isLook = name.hasPrefix("look-")
        guard isLook || clips[name] != nil else { return }
        let count = isLook ? GazeSelector.count : clips[name]!.frames
        let cell = name == "look-0" ? gazeLayout.bodyCell : gazeLayout.eyeCell
        let cw = isLook ? cell[0] : clips[name]!.width
        let ch = isLook ? cell[1] : clips[name]!.height
        let columns = isLook ? gazeLayout.columns : clips[name]!.columns
        frames[name] = (0..<count).map { index in
            let rect = CGRect(x: Double(index % columns * cw) / Double(image.width),
                              y: 1 - Double((index / columns + 1) * ch) / Double(image.height),
                              width: Double(cw) / Double(image.width), height: Double(ch) / Double(image.height))
            let texture = SKTexture(rect: rect, in: atlas)
            texture.filteringMode = .linear; texture.usesMipmaps = atlas.usesMipmaps
            return texture
        }
    }
    func preloadGaze() { for stage in 0..<4 { _ = texture("look-\(stage)") } }
    func purge(except keep: Set<String> = []) {
        let now = ProcessInfo.processInfo.systemUptime
        for name in Array(atlases.keys) where !name.hasPrefix("look-") && !keep.contains(name) && now - (access[name] ?? 0) > 15 {
            frames.removeValue(forKey: name); atlases.removeValue(forKey: name); access.removeValue(forKey: name)
        }
    }
    func purgeAll(except keep: Set<String> = []) {
        for name in Array(atlases.keys) where !keep.contains(name) {
            frames.removeValue(forKey: name); atlases.removeValue(forKey: name); access.removeValue(forKey: name)
        }
    }
    var loadedAtlasCount: Int { atlases.count }
    func portrait() -> NSImage? {
        if let cachedPortrait { return cachedPortrait }
        guard let source = CGImageSourceCreateWithURL(root.appendingPathComponent("portrait.png") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let portrait = NSImage(cgImage: image, size: NSSize(width: 192, height: 208))
        cachedPortrait = portrait; return portrait
    }
}
