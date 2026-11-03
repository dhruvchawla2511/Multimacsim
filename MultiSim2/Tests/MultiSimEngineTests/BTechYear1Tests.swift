import XCTest
@testable import MultiSimEngine

final class BTechYear1Tests: XCTestCase {

    func testKVLAndKCL() {
        // Circuit: 12V DC Source -> R1 (4 ohm) -> Node 2 -> R2 (6 ohm) & R3 (12 ohm) in parallel -> Ground
        // Equivalent R parallel = (6 * 12) / (6 + 12) = 72 / 18 = 4 ohm
        // Total R = 4 + 4 = 8 ohm
        // Total Current = 12 / 8 = 1.5 A
        // Voltage at Node 2 = 1.5 * 4 = 6.0 V
        // Current through R2 = 6 / 6 = 1.0 A
        // Current through R3 = 6 / 12 = 0.5 A
        // KCL at Node 2: 1.5 A (in) = 1.0 A (R2) + 0.5 A (R3) (out) -> verified!
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", value: 12.0)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", value: 4.0)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", value: 6.0)
        let r3 = CircuitComponent(kind: .resistor, designator: "R3", value: 12.0)
        let gnd = CircuitComponent(kind: .ground, designator: "GND")

        let w1 = Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id)
        let w2 = Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id)
        let w3 = Wire(startPinId: r1.pins[1].id, endPinId: r3.pins[0].id)
        let w4 = Wire(startPinId: r2.pins[1].id, endPinId: gnd.pins[0].id)
        let w5 = Wire(startPinId: r3.pins[1].id, endPinId: gnd.pins[0].id)
        let w6 = Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id)

        let circuit = Circuit(
            components: [v1, r1, r2, r3, gnd],
            wires: [w1, w2, w3, w4, w5, w6]
        )

        let solver = MNASolver(circuit: circuit, timeStep: 1e-4)
        let res = solver.step()

        let (pinMap, _) = circuit.resolveNodes()
        let node2Idx = pinMap[r1.pins[1].id]!
        let vNode2 = res.nodeVoltages[node2Idx]!

        XCTAssertEqual(vNode2, 6.0, accuracy: 1e-4)
        XCTAssertEqual(r1.runtimeCurrent, 1.5, accuracy: 1e-4)
        XCTAssertEqual(r2.runtimeCurrent, 1.0, accuracy: 1e-4)
        XCTAssertEqual(r3.runtimeCurrent, 0.5, accuracy: 1e-4)

        // KCL verification
        let kclDelta = abs(r1.runtimeCurrent - (r2.runtimeCurrent + r3.runtimeCurrent))
        XCTAssertLessThan(kclDelta, 1e-6)
    }

    func testTheveninTheorem() {
        // Standard Thevenin problem:
        // 20V source with R1 = 10 ohm, R2 = 40 ohm across ground.
        // Terminal A is at node between R1 and R2, Terminal B is Ground.
        // Vth = 20 * (40 / (10 + 40)) = 16.0 V
        // Rth = 10 || 40 = 400 / 50 = 8.0 ohm
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", value: 20.0)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", value: 10.0)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", value: 40.0)
        let gnd = CircuitComponent(kind: .ground, designator: "GND")

        let w1 = Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id)
        let w2 = Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id)
        let w3 = Wire(startPinId: r2.pins[1].id, endPinId: gnd.pins[0].id)
        let w4 = Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id)

        let circuit = Circuit(
            components: [v1, r1, r2, gnd],
            wires: [w1, w2, w3, w4]
        )

        let (pinMap, _) = circuit.resolveNodes()
        let nodeA = pinMap[r2.pins[0].id]!

        guard let thev = TheveninAnalyzer.computeEquivalent(circuit: circuit, nodeA: nodeA, nodeB: 0) else {
            XCTFail("Should compute Thevenin equivalent")
            return
        }

        XCTAssertEqual(thev.vTh, 16.0, accuracy: 1e-3)
        XCTAssertEqual(thev.rTh, 8.0, accuracy: 1e-2)
        XCTAssertEqual(thev.iNorton, 2.0, accuracy: 1e-2) // 16V / 8 ohm = 2A
        XCTAssertEqual(thev.pMax, (16.0 * 16.0) / (4.0 * 8.0), accuracy: 1e-2) // 8 Watts max power
    }

    func testDependentVCVS() {
        // Circuit: 5V DC Source into R1 (1k) to Ground.
        // Control voltage V_c is across R1 (5V).
        // VCVS has gain mu = 3.0.
        // Output connects to R2 (1k) to Ground.
        // Theoretical VCVS output voltage = 3.0 * 5.0V = 15.0V.
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", value: 5.0)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", value: 1000.0)
        let vcvs = CircuitComponent(kind: .vcvs, designator: "E1", value: 3.0)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", value: 1000.0)
        let gnd = CircuitComponent(kind: .ground, designator: "GND")

        // Input loop
        let w1 = Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id)
        let w2 = Wire(startPinId: r1.pins[1].id, endPinId: gnd.pins[0].id)
        let w3 = Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id)

        // VCVS control pins (Pin 2 = Ctrl+, Pin 3 = Ctrl-)
        let w4 = Wire(startPinId: vcvs.pins[2].id, endPinId: r1.pins[0].id)
        let w5 = Wire(startPinId: vcvs.pins[3].id, endPinId: gnd.pins[0].id)

        // VCVS output pins (Pin 0 = Out+, Pin 1 = Out-)
        let w6 = Wire(startPinId: vcvs.pins[0].id, endPinId: r2.pins[0].id)
        let w7 = Wire(startPinId: vcvs.pins[1].id, endPinId: gnd.pins[0].id)
        let w8 = Wire(startPinId: r2.pins[1].id, endPinId: gnd.pins[0].id)

        let circuit = Circuit(
            components: [v1, r1, vcvs, r2, gnd],
            wires: [w1, w2, w3, w4, w5, w6, w7, w8]
        )

        let solver = MNASolver(circuit: circuit, timeStep: 1e-4)
        let res = solver.step()

        let (pinMap, _) = circuit.resolveNodes()
        let outNode = pinMap[r2.pins[0].id]!
        let vOut = res.nodeVoltages[outNode]!

        XCTAssertEqual(vOut, 15.0, accuracy: 1e-4)
        XCTAssertEqual(r2.runtimeCurrent, 0.015, accuracy: 1e-4) // 15mA
    }

    func testPhasorMetricsCalculation() {
        // Pure sinusoidal test: V = 10 * sin(wt), I = 2 * sin(wt - 60 deg)
        // V_rms = 10 / sqrt(2) = 7.071 V
        // I_rms = 2 / sqrt(2) = 1.414 A
        // Apparent Power S = 7.071 * 1.414 = 10.0 VA
        // Power factor cos(60 deg) = 0.5
        // Active Power P = 10.0 * 0.5 = 5.0 W
        // Reactive Power Q = 10.0 * sin(60 deg) = 8.66 VAR
        var vSamples: [(time: Double, value: Double)] = []
        var iSamples: [(time: Double, value: Double)] = []

        let freq = 50.0 // 50 Hz
        let omega = 2.0 * .pi * freq
        let phi = 60.0 * .pi / 180.0

        for step in 0..<200 {
            let t = Double(step) * (1.0 / (50.0 * 20.0)) // 10 cycles, 20 samples per cycle
            let v = 10.0 * sin(omega * t)
            let i = 2.0 * sin(omega * t - phi)
            vSamples.append((time: t, value: v))
            iSamples.append((time: t, value: i))
        }

        let metrics = PhasorAnalyzer.analyze(voltageSamples: vSamples, currentSamples: iSamples)

        XCTAssertEqual(metrics.vRMS, 10.0 / sqrt(2.0), accuracy: 0.2)
        XCTAssertEqual(metrics.iRMS, 2.0 / sqrt(2.0), accuracy: 0.1)
        XCTAssertEqual(metrics.powerFactor, 0.5, accuracy: 0.05)
        XCTAssertEqual(metrics.activePower, 5.0, accuracy: 0.3)
    }
}
