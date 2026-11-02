import Foundation
import CoreGraphics

/// Back-and-forth strokes over her head, built from 10 Hz pointer samples.
public struct PettingDetector {
    private var samples: [(time: Double, x: Double)] = []
    public init() {}
    /// True once four strokes of at least 12 points happened within two seconds.
    public mutating func add(time: Double, x: Double, overHead: Bool) -> Bool {
        guard overHead else { samples.removeAll(); return false }
        samples.append((time, x)); samples.removeAll { time - $0.time > 2 }
        var runs: [Double] = [], current = 0.0, sign = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) {
            let dx = b.x - a.x
            guard abs(dx) >= 0.5 else { continue }
            let s: Double = dx > 0 ? 1 : -1
            if s != sign { if current > 0 { runs.append(current) }; current = 0; sign = s }
            current += abs(dx)
        }
        if current > 0 { runs.append(current) }
        guard runs.filter({ $0 >= 12 }).count >= 4 else { return false }
        samples.removeAll(); return true
    }
}

/// Continuous-use timer for break reminders. Five idle minutes count as a break.
public struct BreakClock {
    public private(set) var activeSeconds = 0.0
    public init() {}
    public mutating func tick(elapsed: Double, idle: Double, intervalMinutes: Int) -> Bool {
        guard intervalMinutes > 0, idle < 300 else { activeSeconds = 0; return false }
        if idle < 120 { activeSeconds += elapsed }
        guard activeSeconds >= Double(intervalMinutes * 60) else { return false }
        activeSeconds = 0; return true
    }
}

/// Busy/quiet state of local coding agents from their summed CPU use.
public struct AgentActivity {
    public enum Event: Equatable { case started, finished }
    public private(set) var busy = false
    private var busySince: Double?
    private var quietSince: Double?
    public init() {}
    /// `cpuPercent` is the agents' share of one core since the previous sample.
    public mutating func sample(time: Double, cpuPercent: Double) -> Event? {
        if cpuPercent >= 5 {
            quietSince = nil
            if busySince == nil { busySince = time }
            if !busy, let since = busySince, time - since >= 20 { busy = true; return .started }
            return nil
        }
        guard busy else { busySince = nil; return nil }
        if quietSince == nil { quietSince = time }
        guard let quiet = quietSince, time - quiet >= 20 else { return nil }
        let worked = quiet - (busySince ?? quiet)
        busy = false; busySince = nil; quietSince = nil
        return worked >= 45 ? .finished : nil
    }
}

public enum DayPart: Equatable {
    case morning, day, lateNight
    public init(hour: Int) { self = hour >= 23 || hour < 5 ? .lateNight : hour < 10 ? .morning : .day }
}

/// Window top edges she can stand on. Frames are in Cocoa screen coordinates.
public enum WindowLedge {
    public typealias Window = (id: Int, frame: CGRect)
    /// The window whose top edge is under her feet, within `tolerance` points.
    public static func under(feetX: Double, feetY: Double, windows: [Window], tolerance: Double = 24) -> Window? {
        windows.first { abs($0.frame.maxY - feetY) <= tolerance && feetX >= $0.frame.minX + 24 && feetX <= $0.frame.maxX - 24 }
    }
    /// The highest window top she crosses while falling from `fromY` to `toY`.
    public static func landing(feetX: Double, fromY: Double, toY: Double, windows: [Window]) -> Window? {
        windows.filter { $0.frame.maxY <= fromY && $0.frame.maxY >= toY && feetX >= $0.frame.minX + 24 && feetX <= $0.frame.maxX - 24 }
            .max { $0.frame.maxY < $1.frame.maxY }
    }
    /// A window top edge `reach` points above her feet (chest to just over her head): she can grab it.
    public static func grip(feetX: Double, feetY: Double, reach: ClosedRange<Double>, windows: [Window]) -> Window? {
        windows.first { reach.contains($0.frame.maxY - feetY) && feetX >= $0.frame.minX + 24 && feetX <= $0.frame.maxX - 24 }
    }
}

/// A sharp rise in the bowl's remaining share, for the same source and window, is a quota reset.
public struct RefillDetector {
    private var last: (key: String, fraction: Double)?
    public init() {}
    /// Returns the previous fraction when the bowl just refilled by at least `minimumRise`.
    public mutating func update(key: String, fraction: Double?, minimumRise: Double = 0.15) -> Double? {
        guard let fraction else { return nil }   // loading or no data: remember the last known level
        defer { last = (key, fraction) }
        guard let last, last.key == key, fraction - last.fraction >= minimumRise else { return nil }
        return last.fraction
    }
}

extension BowlQuotaReading {
    /// Menu-bar text without the provider name, e.g. "8%", "<1%", "— " or "21% ·旧".
    public var compact: String { label.split(separator: " ").dropFirst().joined(separator: " ") }
}

/// Where she wanders to on her own, and what she looks at once there.
public struct WanderPlan: Equatable {
    public enum Target: Equatable { case window(Int), icon(String), stroll }
    /// Climbing a window's side from the floor up to its top edge.
    public struct Climb: Equatable {
        public var windowID: Int
        public var wallX: Double, top: Double
        /// Facing right means the window is on her right (she climbs its left side).
        public var facingRight: Bool
    }
    public var target: Target
    /// Where she stops on the surface she stands on (the floor or a window top).
    public var stopX: Double
    public var lookAt: CGPoint?
    public var climb: Climb?
}

public enum WanderPlanner {
    /// `surface` is the walkable x-range at her feet. `standOff` is how far from a wall her feet
    /// stay while climbing. Windows reach the floor when their bottom is within `floorReach`.
    public static func plan(feetX: Double, surface: ClosedRange<Double>, onFloor: Bool, floorY: Double,
                            windows: [WindowLedge.Window], icons: [(name: String, frame: CGRect)],
                            allowClimb: Bool, standOff: Double, floorReach: Double = 60, random: () -> Double) -> WanderPlan {
        func clamp(_ x: Double) -> Double { min(surface.upperBound, max(surface.lowerBound, x)) }
        let usable = windows.filter { $0.frame.width >= 200 && $0.frame.height >= 120 }
        let roll = random()
        if !icons.isEmpty && roll < 0.35 {
            let icon = icons[min(icons.count - 1, Int(random() * Double(icons.count)))]
            // Stand below the icon (or as close as the surface allows) and look up at it.
            return WanderPlan(target: .icon(icon.name), stopX: clamp(icon.frame.midX), lookAt: CGPoint(x: icon.frame.midX, y: icon.frame.midY), climb: nil)
        }
        if !usable.isEmpty && roll < 0.85 {
            let window = usable[min(usable.count - 1, Int(random() * Double(usable.count)))]
            let height = window.frame.maxY - floorY
            if allowClimb && onFloor && window.frame.minY <= floorY + floorReach && height >= 150 && height <= 900 && random() < 0.4 {
                let fromLeft = feetX < window.frame.midX
                let wallX = fromLeft ? window.frame.minX : window.frame.maxX
                let stop = wallX + (fromLeft ? -standOff : standOff)
                if surface.contains(stop) {
                    return WanderPlan(target: .window(window.id), stopX: stop, lookAt: nil,
                                      climb: .init(windowID: window.id, wallX: wallX, top: window.frame.maxY, facingRight: fromLeft))
                }
            }
            // Walk to just beside the window and look at its middle.
            let side = feetX < window.frame.midX ? window.frame.minX + 60 : window.frame.maxX - 60
            return WanderPlan(target: .window(window.id), stopX: clamp(side), lookAt: CGPoint(x: window.frame.midX, y: window.frame.midY), climb: nil)
        }
        let span = surface.upperBound - surface.lowerBound
        return WanderPlan(target: .stroll, stopX: surface.lowerBound + span * (0.15 + 0.7 * random()), lookAt: nil, climb: nil)
    }
}
