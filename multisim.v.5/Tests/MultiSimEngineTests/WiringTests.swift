import XCTest
@testable import MultiSimEngine

/// Geometry tests for the orthogonal router and the magnetic auto-connect rules.
final class WiringTests: XCTestCase {

    private let grid = 20.0

    // MARK: - Router

    func testStraightRunBetweenAlignedPinsStaysStraight() {
        let path = WireRouter.route(start: Point2D(x: 100, y: 200), startDir: .right,
                                    end: Point2D(x: 300, y: 200), endDir: .left,
                                    grid: grid, stub: 0)
        XCTAssertEqual(path.count, 2)
        XCTAssertEqual(path.first?.x, 100)
        XCTAssertEqual(path.last?.x, 300)
    }

    func testEverySegmentIsAxisAligned() {
        // A scattered set of end points and lead directions; none of them may produce a diagonal.
        let starts = [Point2D(x: 100, y: 100), Point2D(x: 420, y: 180), Point2D(x: 240, y: 300)]
        let ends = [Point2D(x: 420, y: 300), Point2D(x: 100, y: 180), Point2D(x: 460, y: 100)]
        let dirs: [PinDirection] = [.right, .up, .left, .down]

        for (i, s) in starts.enumerated() {
            let path = WireRouter.route(start: s, startDir: dirs[i % dirs.count],
                                        end: ends[i], endDir: dirs[(i + 1) % dirs.count],
                                        grid: grid)
            for seg in WireRouter.segments(of: path) {
                XCTAssertTrue(seg.a.x == seg.b.x || seg.a.y == seg.b.y,
                              "Segment \(seg.a) -> \(seg.b) is diagonal")
            }
        }
    }

    func testWireFollowsADraggedComponent() {
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 200, y: 200), value: 100)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", position: Point2D(x: 340, y: 200), value: 100)
        let circuit = Circuit(components: [r1, r2], wires: [Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id)])

        let before = circuit.wirePath(circuit.wires[0], grid: grid)
        XCTAssertEqual(before?.first, Point2D(x: 230, y: 200))
        XCTAssertEqual(before?.last, Point2D(x: 310, y: 200))

        // Drag R2 away: the drawn wire must stretch with it, still ending on its terminal.
        r2.position = Point2D(x: 500, y: 340)
        let after = circuit.wirePath(circuit.wires[0], grid: grid)
        XCTAssertEqual(after?.last, Point2D(x: 470, y: 340))
        XCTAssertTrue((after ?? []).count >= 2)
    }

    func testRouteToTapIsOrthogonalAndEndsOnTheWire() {
        let tap = Point2D(x: 300, y: 260)
        let path = WireRouter.routeToTap(start: Point2D(x: 200, y: 200), startDir: .right, tap: tap, grid: grid)
        XCTAssertEqual(path.last, tap)
        for seg in WireRouter.segments(of: path) {
            XCTAssertTrue(seg.a.x == seg.b.x || seg.a.y == seg.b.y)
        }
    }

    /// The meter-below-the-resistor layout used by the Ohm's-law lab: the voltmeter's leads point away
    /// from the series ammeter, so a stubbed corner would otherwise run the wire back over itself.
    func testWireNeverDoublesBackOverItself() {
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 140, y: 240), value: 12.0)
        let am = CircuitComponent(kind: .ammeter, designator: "A1", position: Point2D(x: 280, y: 160))
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 420, y: 160), value: 120.0)
        let vm = CircuitComponent(kind: .voltmeter, designator: "V2", position: Point2D(x: 350, y: 260))
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 500, y: 300))
        let circuit = Circuit(
            components: [v1, am, r1, vm, gnd],
            wires: [
                Wire(startPinId: v1.pins[0].id, endPinId: am.pins[0].id),
                Wire(startPinId: am.pins[1].id, endPinId: r1.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: vm.pins[0].id, endPinId: am.pins[1].id),
                Wire(startPinId: vm.pins[1].id, endPinId: r1.pins[1].id),
                Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
            ])

        for (index, wire) in circuit.wires.enumerated() {
            guard let path = circuit.wirePath(wire, grid: grid) else { continue }
            XCTAssertEqual(path.first, circuit.pinPosition(wire.startPinId), "wire \(index) must start on its terminal")
            XCTAssertEqual(path.last, circuit.pinPosition(wire.endPinId), "wire \(index) must end on its terminal")
            XCTAssertFalse(WireRouter.hasReversal(path), "wire \(index) doubles back over itself: \(path)")
            for seg in WireRouter.segments(of: path) {
                XCTAssertFalse(seg.a == seg.b, "zero length segment in wire \(index): \(path)")
                XCTAssertTrue(seg.a.x == seg.b.x || seg.a.y == seg.b.y, "diagonal in wire \(index): \(seg.a) -> \(seg.b)")
            }
        }
    }

    // MARK: - Magnetic snapping

    func testDragSnapsTerminalsTogether() {
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 200, y: 200), value: 100)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", position: Point2D(x: 250, y: 200), value: 100)
        let circuit = Circuit(components: [r1, r2], wires: [])

        // 10 points apart is inside the magnetic radius but not touching yet.
        XCTAssertTrue(AutoConnect.coincidentPairs(in: circuit).isEmpty)
        XCTAssertEqual(r1.absolutePinPosition(pinIndex: 1), Point2D(x: 230, y: 200))
        XCTAssertEqual(r2.absolutePinPosition(pinIndex: 0), Point2D(x: 220, y: 200))

        guard let snapped = AutoConnect.snappedPosition(moving: r2, proposed: Point2D(x: 250, y: 200), in: circuit, grid: grid) else {
            return XCTFail("the nearby terminal should have grabbed R2")
        }
        r2.position = snapped
        XCTAssertEqual(r2.absolutePinPosition(pinIndex: 0), Point2D(x: 230, y: 200))

        let pairs = AutoConnect.coincidentPairs(in: circuit)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(Set(pairs.first.map { [$0.a, $0.b] } ?? []), [r1.pins[1].id, r2.pins[0].id])
    }

    func testFacingPairsConnectAlongAStraightRun() {
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 200, y: 200), value: 100)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", position: Point2D(x: 320, y: 200), value: 100)
        let r3 = CircuitComponent(kind: .resistor, designator: "R3", position: Point2D(x: 200, y: 420), value: 100)
        let circuit = Circuit(components: [r1, r2, r3], wires: [])

        let pairs = AutoConnect.facingPairs(in: circuit, maxGap: 60, grid: grid)
        XCTAssertEqual(pairs.count, 1, "only the two terminals facing along y=200 should pair up")
        guard let pair = pairs.first else { return XCTFail("expected one facing pair") }
        XCTAssertEqual(pair.from.id, r1.pins[1].id)
        XCTAssertEqual(pair.to.id, r2.pins[0].id)
        XCTAssertEqual(pair.gap, 60, accuracy: 1e-9)
    }

    func testPinDroppedOnAWireFindsTheTapPoint() {
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 200, y: 200), value: 100)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", position: Point2D(x: 400, y: 200), value: 100)
        let wire = Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id)
        let lamp = CircuitComponent(kind: .lamp, designator: "LS1", position: Point2D(x: 300, y: 210), value: 10)
        let circuit = Circuit(components: [r1, r2, lamp], wires: [wire])

        let pin = lamp.absolutePinPosition(pinIndex: 1)
        guard let tap = AutoConnect.nearestTapPoint(from: pin, in: circuit, grid: grid, tolerance: 14, ignoring: nil) else {
            return XCTFail("a terminal 10 points above a wire should find it")
        }
        XCTAssertEqual(tap.wire.id, wire.id)
        XCTAssertEqual(tap.point.y, 200, accuracy: 1e-9)
        XCTAssertEqual(tap.point.x, pin.x, accuracy: 1e-9)
    }

    func testAlreadyConnectedPinsAreNotPairedAgain() {
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 200, y: 200), value: 100)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", position: Point2D(x: 320, y: 200), value: 100)
        let wire = Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id)
        let circuit = Circuit(components: [r1, r2], wires: [wire])

        XCTAssertTrue(AutoConnect.facingPairs(in: circuit, maxGap: 60, grid: grid).isEmpty)
    }
}
