import XCTest
@testable import MultiSimEngine

final class MNASolverTests: XCTestCase {

    func testMatrixSolver() {
        // Test system:
        //  2*x + 1*y = 5
        //  1*x + 3*y = 5
        // Solution: x = 2, y = 1
        var A = Matrix(rows: 2, cols: 2)
        A[0, 0] = 2.0; A[0, 1] = 1.0
        A[1, 0] = 1.0; A[1, 1] = 3.0
        let b = [5.0, 5.0]

        guard let sol = A.solve(b: b) else {
            XCTFail("Matrix should be solvable")
            return
        }

        XCTAssertEqual(sol.count, 2)
        XCTAssertEqual(sol[0], 2.0, accuracy: 1e-6)
        XCTAssertEqual(sol[1], 1.0, accuracy: 1e-6)
    }

    func testVoltageDivider() {
        // Circuit: 10V DC Source -> R1 (1000 ohm) -> Node 2 -> R2 (1000 ohm) -> Ground
        // Expected Node 2 Voltage = 5.0 V
        let vsrc = CircuitComponent(kind: .dcVoltageSource, designator: "V1", value: 10.0)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", value: 1000.0)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", value: 1000.0)
        let gnd = CircuitComponent(kind: .ground, designator: "GND")

        // Connections:
        // V1+ (pin 0) -> R1 (pin 0) [Node 1]
        // R1 (pin 1) -> R2 (pin 0)  [Node 2]
        // R2 (pin 1) -> GND (pin 0) [Node 0]
        // V1- (pin 1) -> GND (pin 0) [Node 0]
        let w1 = Wire(startPinId: vsrc.pins[0].id, endPinId: r1.pins[0].id)
        let w2 = Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id)
        let w3 = Wire(startPinId: r2.pins[1].id, endPinId: gnd.pins[0].id)
        let w4 = Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id)

        let circuit = Circuit(
            components: [vsrc, r1, r2, gnd],
            wires: [w1, w2, w3, w4]
        )

        let solver = MNASolver(circuit: circuit, timeStep: 1e-4)
        let res = solver.step()

        XCTAssertTrue(res.converged)
        let (pinMap, _) = circuit.resolveNodes()
        let node2Idx = pinMap[r2.pins[0].id]!
        let vMid = res.nodeVoltages[node2Idx]!

        XCTAssertEqual(vMid, 5.0, accuracy: 1e-4)
        XCTAssertEqual(r1.runtimeCurrent, 0.005, accuracy: 1e-4) // 5mA
    }

    func testRCTransientStepResponse() {
        // Step response of an RC circuit:
        // 10V step into R = 1k, C = 1uF.
        // Time constant tau = R * C = 1ms.
        // At t = 1ms, V_C = 10 * (1 - e^-1) = 6.3212 V.
        let vsrc = CircuitComponent(kind: .dcVoltageSource, designator: "V1", value: 10.0)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", value: 1000.0)
        let c1 = CircuitComponent(kind: .capacitor, designator: "C1", value: 1e-6)
        let gnd = CircuitComponent(kind: .ground, designator: "GND")

        let w1 = Wire(startPinId: vsrc.pins[0].id, endPinId: r1.pins[0].id)
        let w2 = Wire(startPinId: r1.pins[1].id, endPinId: c1.pins[0].id)
        let w3 = Wire(startPinId: c1.pins[1].id, endPinId: gnd.pins[0].id)
        let w4 = Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id)

        let circuit = Circuit(
            components: [vsrc, r1, c1, gnd],
            wires: [w1, w2, w3, w4]
        )

        let dt = 1e-5 // 10 microseconds step
        let solver = MNASolver(circuit: circuit, timeStep: dt)

        let (pinMap, _) = circuit.resolveNodes()
        let capNodeIdx = pinMap[c1.pins[0].id]!

        // Simulate for 1ms (100 steps)
        for _ in 0..<100 {
            _ = solver.step(dt: dt)
        }

        let vAt1ms = solver.step(dt: dt).nodeVoltages[capNodeIdx]!
        let theoretical = 10.0 * (1.0 - exp(-1.0)) // ~6.3212V
        // With backward Euler at dt=10us, accuracy is well within 0.1V
        XCTAssertEqual(vAt1ms, theoretical, accuracy: 0.1)

        // Simulate up to 5ms (400 more steps) -> capacitor fully charged to ~9.93V
        for _ in 0..<400 {
            _ = solver.step(dt: dt)
        }
        let vAt5ms = solver.step(dt: dt).nodeVoltages[capNodeIdx]!
        XCTAssertEqual(vAt5ms, 10.0, accuracy: 0.1)
    }

    func testDiodeConduction() {
        // 5V DC -> 1k Resistor -> Diode -> Ground
        let vsrc = CircuitComponent(kind: .dcVoltageSource, designator: "V1", value: 5.0)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", value: 1000.0)
        let d1 = CircuitComponent(kind: .diode, designator: "D1")
        let gnd = CircuitComponent(kind: .ground, designator: "GND")

        let w1 = Wire(startPinId: vsrc.pins[0].id, endPinId: r1.pins[0].id)
        let w2 = Wire(startPinId: r1.pins[1].id, endPinId: d1.pins[0].id)
        let w3 = Wire(startPinId: d1.pins[1].id, endPinId: gnd.pins[0].id)
        let w4 = Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id)

        let circuit = Circuit(
            components: [vsrc, r1, d1, gnd],
            wires: [w1, w2, w3, w4]
        )

        let solver = MNASolver(circuit: circuit, timeStep: 1e-4)
        let res = solver.step()

        let (pinMap, _) = circuit.resolveNodes()
        let anodeNode = pinMap[d1.pins[0].id]!
        let vAnode = res.nodeVoltages[anodeNode]!

        // Silicon diode forward voltage drop is typically around 0.65V - 0.75V
        XCTAssertGreaterThan(vAnode, 0.55)
        XCTAssertLessThan(vAnode, 0.80)
        XCTAssertEqual(d1.runtimeCurrent, (5.0 - vAnode) / 1000.0, accuracy: 1e-4)
    }

    func testSPICEExport() {
        let vsrc = CircuitComponent(kind: .dcVoltageSource, designator: "V1", value: 12.0)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", value: 4700.0)
        let gnd = CircuitComponent(kind: .ground, designator: "GND")

        let w1 = Wire(startPinId: vsrc.pins[0].id, endPinId: r1.pins[0].id)
        let w2 = Wire(startPinId: r1.pins[1].id, endPinId: gnd.pins[0].id)
        let w3 = Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id)

        let circuit = Circuit(
            components: [vsrc, r1, gnd],
            wires: [w1, w2, w3]
        )

        let netlist = SPICEExporter.export(circuit: circuit, title: "Test Divider")
        XCTAssertTrue(netlist.contains("V1"))
        XCTAssertTrue(netlist.contains("R1"))
        XCTAssertTrue(netlist.contains("4.7k"))
        XCTAssertTrue(netlist.contains(".tran"))
        XCTAssertTrue(netlist.contains(".end"))
    }
}
