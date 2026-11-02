import Foundation

public struct Vector: Equatable, Codable {
    public var x: Double; public var y: Double
    public init(_ x: Double = 0, _ y: Double = 0) { self.x = x; self.y = y }
    public var length: Double { hypot(x, y) }
    public static func + (a: Self, b: Self) -> Self { .init(a.x + b.x, a.y + b.y) }
    public static func - (a: Self, b: Self) -> Self { .init(a.x - b.x, a.y - b.y) }
    public static func * (a: Self, b: Double) -> Self { .init(a.x * b, a.y * b) }
    public func limited(to limit: Double) -> Self { length > limit ? self * (limit / length) : self }
}
public struct MotionBounds {
    public var minX: Double; public var minY: Double; public var maxX: Double; public var maxY: Double
    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) { self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY }
    public func clamp(_ p: Vector) -> Vector { .init(min(maxX, max(minX, p.x)), min(maxY, max(minY, p.y))) }
}
public struct BowlMotion {
    public var position: Vector
    public var velocity: Vector
    public var angle = 0.0
    public var angularVelocity: Double
    public private(set) var settled = false
    public init(position: Vector, velocity: Vector) {
        self.position = position; self.velocity = velocity.limited(to: 1600)
        angularVelocity = min(12, max(-12, velocity.x / 90))
    }
    public mutating func step(dt: Double, bounds: MotionBounds, bounce: Double) {
        guard !settled else { return }
        let dt = min(1.0 / 20, max(0, dt))
        velocity.y -= 1350 * dt
        position = position + velocity * dt
        angle += angularVelocity * dt
        if position.x < bounds.minX || position.x > bounds.maxX { velocity.x *= -0.55; position = bounds.clamp(position) }
        if position.y > bounds.maxY { position.y = bounds.maxY; velocity.y = -abs(velocity.y) * 0.4 }
        if position.y <= bounds.minY {
            position.y = bounds.minY
            velocity.y = abs(velocity.y) * min(0.7, max(0, bounce))
            velocity.x *= 0.7; angularVelocity *= 0.65
            if velocity.y < 65 { velocity.y = 0; velocity.x *= exp(-dt * 15) }
            if velocity.length < 20 { velocity = .init(); angularVelocity = 0; settled = true }
        }
    }
}
public struct ThrowSampler {
    private var samples: [(Double, Vector)] = []
    public init() {}
    public mutating func add(time: Double, position: Vector) {
        samples.append((time, position)); samples.removeAll { time - $0.0 > 0.12 }
        if samples.count > 16 { samples.removeFirst(samples.count - 16) }
    }
    public func velocity() -> Vector {
        guard let first = samples.first, let last = samples.last, last.0 - first.0 > 0.008 else { return .init() }
        return ((last.1 - first.1) * (1 / (last.0 - first.0))).limited(to: 1600)
    }
}
public struct GazeSelector {
    public static let count = 32
    public private(set) var direction = 0
    public init() {}
    public mutating func update(dx: Double, dy: Double, overBody: Bool = false) -> Int {
        if overBody { direction = 0; return direction }
        guard hypot(dx, dy) > 25 else { return direction }
        guard dx.isFinite, dy.isFinite else { return direction }
        var raw = atan2(dx, dy) / (2 * .pi) * Double(Self.count)
        if raw < 0 { raw += Double(Self.count) }
        let delta = abs(raw - Double(direction))
        if min(delta, Double(Self.count) - delta) > 0.65 { direction = Int(raw.rounded()) % Self.count }
        return direction
    }
}
/// Time-based following in circular direction space. The shortest turn crosses 31/0
/// normally; a large pointer jump never snaps directly across the character.
public struct GazeFollower {
    public private(set) var position = 0.0
    public private(set) var target = 0
    public init() {}
    private var delta: Double {
        let n = Double(GazeSelector.count)
        var d = Double(target) - position
        if d > n / 2 { d -= n }; if d < -n / 2 { d += n }
        return d
    }
    public var isTurning: Bool { abs(delta) > 0.015 }
    public var direction: Int { Int(position.rounded()) % GazeSelector.count }
    public mutating func aim(at direction: Int, immediately: Bool = false) {
        target = (direction % GazeSelector.count + GazeSelector.count) % GazeSelector.count
        if immediately { position = Double(target) }
    }
    public mutating func advance(dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        let dt = min(0.05, dt), d = delta
        let eased = d * (1 - exp(-dt / 0.055))
        let maximum = 600.0 / 360 * Double(GazeSelector.count) * dt
        let step = max(-maximum, min(maximum, eased))
        let n = Double(GazeSelector.count)
        position = (position + step + n).truncatingRemainder(dividingBy: n)
        if abs(delta) <= 0.015 { position = Double(target) }
    }
}
public struct StoryBag {
    private var pending: [Story] = []
    private var previous: Story?
    public init() {}
    public mutating func next(enabled: [Story]) -> Story? {
        pending.removeAll { !enabled.contains($0) }
        guard !enabled.isEmpty else { return nil }
        if pending.isEmpty {
            pending = enabled.shuffled()
            if pending.count > 1, pending.last == previous { pending.swapAt(0, pending.count - 1) }
        }
        previous = pending.removeLast(); return previous
    }
}
