import Foundation

/// Geometry helpers that decide what "connected" means on the schematic.
///
/// These live in the engine so the wiring behaviour can be unit tested without SwiftUI.
public enum AutoConnect {
    /// Default distance a terminal will reach out and grab another terminal (canvas points).
    public static let snapRadius: Double = 18

    /// Extra distance tolerated when a pin is aligned along a lead that already points at its target.
    public static let facingGapLimit: Double = 60

    /// How close a pin must land to an existing wire to be considered a tap.
    public static let wireTapTolerance: Double = 10

    /// Magnetic position for a dragged part.
    ///
    /// Returns a nudged position where one or more of the moving part's terminals line up exactly with
    /// another terminal (or sit on an existing wire), so connections form on drop instead of by luck.
    public static func snappedPosition(
        moving comp: CircuitComponent,
        proposed: Point2D,
        in circuit: Circuit,
        radius: Double = snapRadius,
        grid: Double = 20
    ) -> Point2D? {
        var best: (position: Point2D, score: Int, error: Double)?

        func consider(_ candidate: Point2D, error: Double) {
            let score = alignedPinCount(of: comp, at: candidate, in: circuit)
            guard score > 0 else { return }
            if best == nil || score > best!.score || (score == best!.score && error < best!.error) {
                best = (candidate, score, error)
            }
        }

        // Pin onto pin.
        for pin in comp.pins {
            let src = comp.absolutePinPosition(pinIndex: pin.index, at: proposed)
            for other in circuit.components where other.id != comp.id {
                for otherPin in other.pins {
                    let tgt = other.absolutePinPosition(pinIndex: otherPin.index)
                    let delta = tgt - src
                    let error = delta.distance(to: .zero)
                    guard error <= radius else { continue }
                    consider(proposed + delta, error: error)
                }
            }
        }

        // Pin onto an existing wire (T-junction).
        for pin in comp.pins {
            let src = comp.absolutePinPosition(pinIndex: pin.index, at: proposed)
            guard let tap = nearestTapPoint(from: src, in: circuit, grid: grid, tolerance: radius) else { continue }
            consider(proposed + (tap.point - src), error: tap.point.distance(to: src))
        }

        return best?.position
    }

    /// Number of this component's terminals that sit exactly on another terminal (or on a wire) at a position.
    public static func alignedPinCount(of comp: CircuitComponent, at position: Point2D, in circuit: Circuit) -> Int {
        var count = 0
        for pin in comp.pins {
            let p = comp.absolutePinPosition(pinIndex: pin.index, at: position)
            let onPin = circuit.components.contains { other in
                other.id != comp.id
                    && other.pins.contains { other.absolutePinPosition(pinIndex: $0.index).distance(to: p) < 0.5 }
            }
            if onPin { count += 1; continue }
            if nearestTapPoint(from: p, in: circuit, grid: 20, tolerance: 1.5) != nil { count += 1 }
        }
        return count
    }

    /// Closest point on any wire polyline to `p`.
    public static func nearestTapPoint(
        from p: Point2D,
        in circuit: Circuit,
        grid: Double,
        tolerance: Double,
        ignoring wireId: UUID? = nil
    ) -> (wire: Wire, point: Point2D, distance: Double)? {
        var best: (wire: Wire, point: Point2D, distance: Double)?
        for wire in circuit.wires where wire.id != wireId {
            guard let path = circuit.wirePath(wire, grid: grid) else { continue }
            for seg in 0..<(path.count - 1) {
                let a = path[seg]
                let b = path[seg + 1]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let lenSq = dx * dx + dy * dy
                let t = lenSq == 0 ? 0 : min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq, 0), 1)
                let proj = Point2D(x: a.x + t * dx, y: a.y + t * dy)
                let d = proj.distance(to: p)
                if d <= tolerance, d < (best?.distance ?? .greatestFiniteMagnitude) {
                    best = (wire, proj, d)
                }
            }
        }
        return best
    }

    /// Terminal pairs that already face each other along a straight, unconnected run.
    ///
    /// This is what the Auto-Connect action uses: two leads pointing at each other on the same row or
    /// column get a wire between them without the user drawing it.
    public static func facingPairs(in circuit: Circuit, maxGap: Double = facingGapLimit, grid: Double = 20) -> [(from: Pin, to: Pin, gap: Double, fromComp: UUID, toComp: UUID)] {
        var pairs: [(from: Pin, to: Pin, gap: Double, fromComp: UUID, toComp: UUID)] = []
        var seen = Set<String>()
        let pinToNode = circuit.resolveNodes().pinToNode

        func alreadyConnected(_ a: UUID, _ b: UUID) -> Bool {
            guard let na = pinToNode[a], let nb = pinToNode[b] else { return false }
            return na == nb
        }

        for comp in circuit.components {
            for pin in comp.pins {
                let a = comp.absolutePinPosition(pinIndex: pin.index)
                let dirA = comp.pinExitDirection(pinIndex: pin.index)

                for other in circuit.components where other.id != comp.id {
                    for otherPin in other.pins {
                        guard !alreadyConnected(pin.id, otherPin.id) else { continue }
                        // Each pair is reported once, from the part that comes first in the schematic.
                        let key = pin.id.uuidString < otherPin.id.uuidString
                            ? "\(pin.id)-\(otherPin.id)" : "\(otherPin.id)-\(pin.id)"
                        guard seen.insert(key).inserted else { continue }
                        let b = other.absolutePinPosition(pinIndex: otherPin.index)
                        let dirB = other.pinExitDirection(pinIndex: otherPin.index)

                        // Leads must point at each other and be on the same axis.
                        guard opposite(dirA, dirB) else { continue }
                        let gap: Double
                        if dirA.isHorizontal {
                            guard a.y == b.y else { continue }
                            gap = abs(a.x - b.x)
                            let facing = (dirA == .right && b.x > a.x) || (dirA == .left && b.x < a.x)
                            guard facing, gap > 0.5, gap <= maxGap else { continue }
                        } else {
                            guard a.x == b.x else { continue }
                            gap = abs(a.y - b.y)
                            let facing = (dirA == .down && b.y > a.y) || (dirA == .up && b.y < a.y)
                            guard facing, gap > 0.5, gap <= maxGap else { continue }
                        }
                        pairs.append((pin, otherPin, gap, comp.id, other.id))
                    }
                }
            }
        }

        return pairs.sorted { $0.gap < $1.gap }
    }

    /// Pins that physically coincide - these are connected even when no wire object was drawn.
    public static func coincidentPairs(in circuit: Circuit, tolerance: Double = 1.5) -> [(a: UUID, b: UUID)] {
        var result: [(UUID, UUID)] = []
        var seen = Set<String>()
        for (i, compA) in circuit.components.enumerated() {
            for pinA in compA.pins {
                let pa = compA.absolutePinPosition(pinIndex: pinA.index)
                for j in (i + 1)..<circuit.components.count {
                    let compB = circuit.components[j]
                    for pinB in compB.pins {
                        let pb = compB.absolutePinPosition(pinIndex: pinB.index)
                        guard pa.distance(to: pb) <= tolerance else { continue }
                        let key = pinA.id.uuidString < pinB.id.uuidString
                            ? "\(pinA.id)-\(pinB.id)" : "\(pinB.id)-\(pinA.id)"
                        if seen.insert(key).inserted {
                            result.append((pinA.id, pinB.id))
                        }
                    }
                }
            }
        }
        return result
    }

    private static func opposite(_ a: PinDirection, _ b: PinDirection) -> Bool {
        switch (a, b) {
        case (.left, .right), (.right, .left), (.up, .down), (.down, .up): return true
        default: return false
        }
    }
}

extension Circuit {
    /// The drawn path of a wire, computed from where its terminals are right now.
    public func wirePath(_ wire: Wire, grid: Double) -> [Point2D]? {
        guard let startOwner = component(owningPin: wire.startPinId),
              let endOwner = component(owningPin: wire.endPinId) else { return nil }

        let start = startOwner.component.absolutePinPosition(pinIndex: startOwner.pin.index)
        let end = endOwner.component.absolutePinPosition(pinIndex: endOwner.pin.index)
        let dirStart = startOwner.component.pinExitDirection(pinIndex: startOwner.pin.index)
        let dirEnd = endOwner.component.pinExitDirection(pinIndex: endOwner.pin.index)

        // A lone waypoint means this wire was tapped onto another wire: draw the stub into that point.
        if wire.waypoints.count == 1, wire.startPinId != wire.endPinId {
            let tap = wire.waypoints[0]
            if tap.distance(to: end) <= 2.0 {
                return WireRouter.routeToTap(start: start, startDir: dirStart, tap: tap, grid: grid)
            }
        }

        return WireRouter.route(
            start: start,
            startDir: dirStart,
            end: end,
            endDir: dirEnd,
            grid: grid,
            via: wire.waypoints
        )
    }

    /// True when two pins already belong to the same electrical net.
    public func isConnected(_ pinA: UUID, _ pinB: UUID) -> Bool {
        let (pinToNode, _) = resolveNodes()
        guard let na = pinToNode[pinA], let nb = pinToNode[pinB] else { return false }
        return na == nb
    }
}
