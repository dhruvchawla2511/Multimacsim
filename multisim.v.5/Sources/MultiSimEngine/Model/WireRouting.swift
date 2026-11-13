import Foundation

/// Routes a wire between two terminals as axis-aligned segments that leave each pin straight along its lead.
///
/// Wires are computed from the live pin positions rather than stored, so a connection keeps following the
/// part when it is dragged. Everything lands on the grid, which is what makes a bundle of connections
/// read as clean straight runs instead of spaghetti.
public enum WireRouter {
    /// Full path from `start` to `end`, including both endpoints.
    /// - Parameter via: Optional intermediate points a wire must pass through (T-junction taps).
    public static func route(
        start: Point2D,
        startDir: PinDirection,
        end: Point2D,
        endDir: PinDirection,
        grid: Double,
        stub: Double? = nil,
        via: [Point2D] = []
    ) -> [Point2D] {
        let lead = stub ?? grid
        let s1 = stubPoint(start, startDir, lead: lead, grid: grid)
        let s2 = stubPoint(end, endDir, lead: lead, grid: grid)

        var path = [start, s1]
        if via.isEmpty {
            path.append(contentsOf: join(from: s1, leaving: startDir, to: s2, entering: endDir, grid: grid))
        } else {
            var cursor = s1
            var cursorDir = startDir
            for point in via {
                let target = snap(point, to: grid)
                path.append(contentsOf: join(from: cursor, leaving: cursorDir, to: target, entering: cursorDir, grid: grid))
                cursor = target
                cursorDir = cursorDir.isHorizontal ? .down : .right
            }
            path.append(contentsOf: join(from: cursor, leaving: cursorDir, to: s2, entering: endDir, grid: grid))
        }
        path.append(s2)
        path.append(end)

        // Detect the doubling back on the raw path: once `simplify` removes a collinear corner the
        // reversed leg can shrink to nothing and stop looking like a reversal at all.
        guard hasReversal(path) else { return simplify(path) }
        // Two leads facing away from each other, or a stub that lands past its own pin, cannot be joined
        // by a stubbed Z without the line running back over itself. Drop the stubs in that case.
        return stubFreeRun([start] + via.map { snap($0, to: grid) } + [end], leaving: startDir)
    }

    /// Orthogonal polyline through `ordered` points, taking the first leg along `startDir`.
    static func stubFreeRun(_ ordered: [Point2D], leaving startDir: PinDirection) -> [Point2D] {
        guard let first = ordered.first else { return [] }
        var out = [first]
        var wantHorizontal = startDir.isHorizontal
        for target in ordered.dropFirst() {
            let from = out[out.count - 1]
            if from.x == target.x || from.y == target.y {
                out.append(target)
                continue
            }
            out.append(wantHorizontal ? Point2D(x: target.x, y: from.y) : Point2D(x: from.x, y: target.y))
            out.append(target)
            wantHorizontal.toggle()
        }
        return simplify(out)
    }

    /// True when the polyline ever reverses along an axis, i.e. the wire doubles back over itself.
    static func hasReversal(_ points: [Point2D]) -> Bool {
        let segs = segments(of: points)
        for i in 1..<segs.count {
            let p = segs[i - 1], q = segs[i]
            let horizontal = p.a.y == p.b.y && q.a.y == q.b.y
            let vertical = p.a.x == p.b.x && q.a.x == q.b.x
            if horizontal, (p.b.x - p.a.x) * (q.b.x - q.a.x) < 0 { return true }
            if vertical, (p.b.y - p.a.y) * (q.b.y - q.a.y) < 0 { return true }
        }
        return false
    }

    /// Path from a terminal out to a point on an existing wire (used when a pin is dropped onto a wire).
    public static func routeToTap(start: Point2D, startDir: PinDirection, tap: Point2D, grid: Double) -> [Point2D] {
        let s1 = stubPoint(start, startDir, lead: grid, grid: grid)
        let target = snap(tap, to: grid)
        var path = [start, s1]
        path.append(contentsOf: join(from: s1, leaving: startDir, to: target, entering: startDir, grid: grid))
        path.append(target)
        if hasReversal(path) {
            // The tap sits behind the lead; a single corner out of the pin reads better than a stub
            // that has to turn around.
            return stubFreeRun([start, target], leaving: startDir)
        }
        return simplify(path)
    }

    /// The point just outside a pin, along the lead it exits through.
    static func stubPoint(_ pin: Point2D, _ dir: PinDirection, lead: Double, grid: Double) -> Point2D {
        let raw = Point2D(x: pin.x + dir.unit.x * lead, y: pin.y + dir.unit.y * lead)
        // Keep the coordinate that is shared with the pin exact, so the first segment is never diagonal.
        if dir.isHorizontal {
            return Point2D(x: snap(raw.x, to: grid), y: pin.y)
        }
        return Point2D(x: pin.x, y: snap(raw.y, to: grid))
    }

    /// Intermediate corner points between two axis-aligned stubs.
    static func join(
        from a: Point2D,
        leaving dirA: PinDirection,
        to b: Point2D,
        entering dirB: PinDirection,
        grid: Double
    ) -> [Point2D] {
        if a == b { return [] }

        // Already a straight run.
        if (a.y == b.y && dirA.isHorizontal && dirB.isHorizontal)
            || (a.x == b.x && dirA.isVertical && dirB.isVertical) {
            return []
        }

        // One corner is enough when the leads are perpendicular.
        if dirA.isHorizontal != dirB.isHorizontal {
            let corner = dirA.isHorizontal
                ? Point2D(x: snap(b.x, to: grid), y: a.y)
                : Point2D(x: a.x, y: snap(b.y, to: grid))
            return [corner]
        }

        // Parallel leads: step across at the midpoint between them.
        if dirA.isHorizontal {
            let midX = snap((a.x + b.x) / 2.0, to: grid)
            return [Point2D(x: midX, y: a.y), Point2D(x: midX, y: b.y)]
        }
        let midY = snap((a.y + b.y) / 2.0, to: grid)
        return [Point2D(x: a.x, y: midY), Point2D(x: b.x, y: midY)]
    }

    /// Drops repeated points and merges collinear corners so drawn and hit-tested paths stay minimal.
    public static func simplify(_ points: [Point2D]) -> [Point2D] {
        let unique = dropRepeats(points)

        var result: [Point2D] = []
        for i in 0..<unique.count {
            if i == 0 || i == unique.count - 1 {
                result.append(unique[i])
                continue
            }
            let prev = unique[i - 1]
            let cur = unique[i]
            let next = unique[i + 1]
            let collinear = (prev.x == cur.x && cur.x == next.x) || (prev.y == cur.y && cur.y == next.y)
            if !collinear {
                result.append(cur)
            }
        }
        // Removing a corner can bring two identical neighbours together.
        return dropRepeats(result)
    }

    private static func dropRepeats(_ points: [Point2D]) -> [Point2D] {
        var unique: [Point2D] = []
        for p in points where unique.last != p {
            unique.append(p)
        }
        return unique
    }

    /// Rounds a coordinate to the nearest grid line.
    public static func snap(_ value: Double, to grid: Double) -> Double {
        guard grid > 0 else { return value }
        return (value / grid).rounded() * grid
    }

    public static func snap(_ p: Point2D, to grid: Double) -> Point2D {
        Point2D(x: snap(p.x, to: grid), y: snap(p.y, to: grid))
    }

    /// Shortest distance from a point to a polyline - used for selecting a wire with a click.
    public static func distance(from p: Point2D, toPolyline points: [Point2D]) -> Double {
        guard points.count >= 2 else { return .greatestFiniteMagnitude }
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(points.count - 1) {
            best = min(best, distance(from: p, toSegment: points[i], points[i + 1]))
        }
        return best
    }

    public static func distance(from p: Point2D, toSegment a: Point2D, _ b: Point2D) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return p.distance(to: a) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// True when two polylines share a segment overlap - used to keep parallel runs apart visually.
    public static func segments(of points: [Point2D]) -> [(a: Point2D, b: Point2D)] {
        guard points.count >= 2 else { return [] }
        return (0..<(points.count - 1)).map { (points[$0], points[$0 + 1]) }
    }
}
