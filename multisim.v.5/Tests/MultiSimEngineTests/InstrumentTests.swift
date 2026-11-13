import XCTest
@testable import MultiSimEngine

/// Lab-bench behaviour of the measuring instruments: correct reading, and correct non-interference.
final class InstrumentTests: XCTestCase {

    private func solve(_ circuit: Circuit, steps: Int = 1) -> SimulationStepResult {
        let solver = MNASolver(circuit: circuit, timeStep: 1e-4)
        var res = solver.step()
        for _ in 1..<steps { res = solver.step() }
        return res
    }

    // MARK: - Ammeter & voltmeter

    func testAmmeterAndVoltmeterOnOhmsLaw() {
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 12.0)
        let am = CircuitComponent(kind: .ammeter, designator: "A1", position: Point2D(x: 220, y: 200), value: 1e-3)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 340, y: 200), value: 120.0)
        let vm = CircuitComponent(kind: .voltmeter, designator: "V2", position: Point2D(x: 280, y: 300), value: 1e7)
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 420, y: 320))

        let circuit = Circuit(components: [v1, am, r1, vm, gnd], wires: [
            Wire(startPinId: v1.pins[0].id, endPinId: am.pins[0].id),
            Wire(startPinId: am.pins[1].id, endPinId: r1.pins[0].id),
            Wire(startPinId: r1.pins[1].id, endPinId: gnd.pins[0].id),
            Wire(startPinId: vm.pins[0].id, endPinId: am.pins[1].id),
            Wire(startPinId: vm.pins[1].id, endPinId: r1.pins[1].id),
            Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
        ])

        _ = solve(circuit)

        XCTAssertEqual(am.runtimeReading, 0.1, accuracy: 1e-4, "I = 12V / 120Ω")
        XCTAssertEqual(vm.runtimeReading, 12.0, accuracy: 1e-2, "the voltmeter sits across the resistor")
    }

    func testIdealMetersDoNotLoadTheCircuit() {
        func current(withVoltmeter: Bool) -> Double {
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 12.0)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 240, y: 200), value: 120.0)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 320, y: 320))
            var comps = [v1, r1, gnd]
            var wires = [
                Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
            ]
            if withVoltmeter {
                let vm = CircuitComponent(kind: .voltmeter, designator: "V2", position: Point2D(x: 170, y: 300), value: 1e7)
                comps.append(vm)
                wires.append(Wire(startPinId: vm.pins[0].id, endPinId: r1.pins[0].id))
                wires.append(Wire(startPinId: vm.pins[1].id, endPinId: r1.pins[1].id))
            }
            _ = solve(Circuit(components: comps, wires: wires))
            return r1.runtimeCurrent
        }

        XCTAssertEqual(current(withVoltmeter: false), current(withVoltmeter: true), accuracy: 1e-6)
    }

    func testMultimeterSwitchesBetweenModes() {
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 12.0)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 340, y: 200), value: 120.0)
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 420, y: 320))

        // Voltage mode: across the resistor, high input resistance.
        let dmmV = CircuitComponent(kind: .multimeter, designator: "DMM1", position: Point2D(x: 220, y: 300),
                                    value: 1e7, modeIndex: MeterMode.voltage.rawValue)
        let voltCircuit = Circuit(components: [v1, r1, dmmV, gnd], wires: [
            Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id),
            Wire(startPinId: r1.pins[1].id, endPinId: gnd.pins[0].id),
            Wire(startPinId: dmmV.pins[0].id, endPinId: r1.pins[0].id),
            Wire(startPinId: dmmV.pins[1].id, endPinId: r1.pins[1].id),
            Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
        ])
        _ = solve(voltCircuit)
        XCTAssertEqual(dmmV.runtimeReading, 12.0, accuracy: 1e-2)

        // Current mode: in series, tiny burden resistance.
        let v2 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 12.0)
        let r2 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 340, y: 200), value: 120.0)
        let gnd2 = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 420, y: 320))
        let dmmA = CircuitComponent(kind: .multimeter, designator: "DMM1", position: Point2D(x: 220, y: 200),
                                    value: 1e-3, modeIndex: MeterMode.current.rawValue)
        let ampCircuit = Circuit(components: [v2, dmmA, r2, gnd2], wires: [
            Wire(startPinId: v2.pins[0].id, endPinId: dmmA.pins[0].id),
            Wire(startPinId: dmmA.pins[1].id, endPinId: r2.pins[0].id),
            Wire(startPinId: r2.pins[1].id, endPinId: gnd2.pins[0].id),
            Wire(startPinId: v2.pins[1].id, endPinId: gnd2.pins[0].id),
        ])
        _ = solve(ampCircuit)
        XCTAssertEqual(dmmA.runtimeReading, 0.1, accuracy: 1e-4)
    }

    // MARK: - Ohmmeter, wattmeter, galvanometer

    func testOhmmeterReadsTheUnknownResistance() {
        let ohm = CircuitComponent(kind: .ohmmeter, designator: "OHM1", position: Point2D(x: 160, y: 200), value: 1e-3)
        let rx = CircuitComponent(kind: .resistor, designator: "RX", position: Point2D(x: 300, y: 200), value: 470.0)
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 380, y: 300))

        let circuit = Circuit(components: [ohm, rx, gnd], wires: [
            Wire(startPinId: ohm.pins[0].id, endPinId: rx.pins[0].id),
            Wire(startPinId: rx.pins[1].id, endPinId: gnd.pins[0].id),
            Wire(startPinId: ohm.pins[1].id, endPinId: gnd.pins[0].id),
        ])
        _ = solve(circuit)

        XCTAssertEqual(ohm.runtimeReading, 470.0, accuracy: 1.0, "R = V_test / I_test")
    }

    func testWattmeterReadsLoadPower() {
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 12.0)
        let w = CircuitComponent(kind: .wattmeter, designator: "W1", position: Point2D(x: 240, y: 200),
                                 value: 0.05, secondaryValue: 1e6)
        let rl = CircuitComponent(kind: .resistor, designator: "R_LOAD", position: Point2D(x: 380, y: 200), value: 100.0)
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 460, y: 320))

        let circuit = Circuit(components: [v1, w, rl, gnd], wires: [
            // Current coil in series with the load.
            Wire(startPinId: v1.pins[0].id, endPinId: w.pins[0].id),
            Wire(startPinId: w.pins[1].id, endPinId: rl.pins[0].id),
            // Pressure coil across the load.
            Wire(startPinId: w.pins[2].id, endPinId: rl.pins[0].id),
            Wire(startPinId: w.pins[3].id, endPinId: rl.pins[1].id),
            Wire(startPinId: rl.pins[1].id, endPinId: gnd.pins[0].id),
            Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
        ])
        _ = solve(circuit)

        // P = V * I ≈ 12 * 0.12 = 1.44 W
        XCTAssertEqual(w.runtimeReading, 1.44, accuracy: 0.02)
        XCTAssertEqual(w.runtimeCurrent, 0.12, accuracy: 0.005)
    }

    func testGalvanometerDeflectionScalesWithCurrent() {
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 12.0)
        let rs = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 240, y: 200), value: 11_900.0)
        let g = CircuitComponent(kind: .galvanometer, designator: "G1", position: Point2D(x: 380, y: 200),
                                 value: 100.0, secondaryValue: 1e-3)
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 460, y: 320))

        let circuit = Circuit(components: [v1, rs, g, gnd], wires: [
            Wire(startPinId: v1.pins[0].id, endPinId: rs.pins[0].id),
            Wire(startPinId: rs.pins[1].id, endPinId: g.pins[0].id),
            Wire(startPinId: g.pins[1].id, endPinId: gnd.pins[0].id),
            Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
        ])
        _ = solve(circuit)

        XCTAssertEqual(g.runtimeReading, 1e-3, accuracy: 1e-6)
        XCTAssertEqual(MNASolver.galvanometerDeflection(of: g), 1.0, accuracy: 1e-3, "full-scale deflection")
    }

    // MARK: - Potentiometer, fuse, sensor parts

    func testPotentiometerActsAsPotentialDivider() {
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 10.0)
        let pot = CircuitComponent(kind: .potentiometer, designator: "RV1", position: Point2D(x: 260, y: 200),
                                   value: 10_000.0, secondaryValue: 0.3)
        let probe = CircuitComponent(kind: .probe, designator: "P1", position: Point2D(x: 400, y: 260))
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 340, y: 340))

        let circuit = Circuit(components: [v1, pot, probe, gnd], wires: [
            Wire(startPinId: v1.pins[0].id, endPinId: pot.pins[0].id),
            Wire(startPinId: pot.pins[1].id, endPinId: gnd.pins[0].id),
            Wire(startPinId: pot.pins[2].id, endPinId: probe.pins[0].id),
            Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
        ])
        _ = solve(circuit)

        // 3 k from A to W, 7 k from W to B and no load on the wiper -> 7 V.
        XCTAssertEqual(probe.runtimeReading, 7.0, accuracy: 1e-3)
    }

    func testPotentiometerAsVariableLoad() {
        func currentAtRatio(_ ratio: Double) -> Double {
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 12.0)
            let pot = CircuitComponent(kind: .potentiometer, designator: "RV1", position: Point2D(x: 260, y: 200),
                                       value: 500.0, secondaryValue: ratio)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 340, y: 340))
            let circuit = Circuit(components: [v1, pot, gnd], wires: [
                Wire(startPinId: v1.pins[0].id, endPinId: pot.pins[0].id),
                Wire(startPinId: pot.pins[2].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
            ])
            _ = solve(circuit)
            return pot.runtimeCurrent
        }

        XCTAssertEqual(currentAtRatio(0.2), 12.0 / 100.0, accuracy: 1e-3)
        XCTAssertEqual(currentAtRatio(0.5), 12.0 / 250.0, accuracy: 1e-3)
    }

    func testFuseOpensOnOvercurrentAndCanBeReset() {
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 12.0)
        let fuse = CircuitComponent(kind: .fuse, designator: "F1", position: Point2D(x: 240, y: 200),
                                    value: 0.05, secondaryValue: 0.5, stateBool: true)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 380, y: 200), value: 1.0)
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 460, y: 320))

        let circuit = Circuit(components: [v1, fuse, r1, gnd], wires: [
            Wire(startPinId: v1.pins[0].id, endPinId: fuse.pins[0].id),
            Wire(startPinId: fuse.pins[1].id, endPinId: r1.pins[0].id),
            Wire(startPinId: r1.pins[1].id, endPinId: gnd.pins[0].id),
            Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
        ])

        let solver = MNASolver(circuit: circuit, timeStep: 1e-4)
        XCTAssertTrue(fuse.stateBool)
        _ = solver.step()
        XCTAssertFalse(fuse.stateBool, "11 A through a 0.5 A fuse must blow it")

        _ = solver.step()
        XCTAssertEqual(abs(r1.runtimeCurrent), 0.0, accuracy: 1e-5, "an open fuse stops the circuit")

        solver.resetFuses()
        XCTAssertTrue(fuse.stateBool)
    }

    func testThermistorAndLDRTrackTheirEnvironment() {
        let hot = CircuitComponent(kind: .thermistor, designator: "TH1", position: Point2D(x: 100, y: 200),
                                   value: 10_000.0, secondaryValue: 25)
        XCTAssertEqual(resolvedResistance(of: hot) ?? -1, 10_000.0, accuracy: 1.0, "R25 is the rating itself")

        hot.secondaryValue = 85
        guard let raised = resolvedResistance(of: hot) else { return XCTFail("thermistor should resolve a resistance") }
        XCTAssertLessThan(raised, 2_500, "NTC resistance falls sharply with temperature")

        let lit = CircuitComponent(kind: .photoResistor, designator: "LDR1", position: Point2D(x: 200, y: 200),
                                   value: 5_000.0, secondaryValue: 1000)
        let dark = CircuitComponent(kind: .photoResistor, designator: "LDR2", position: Point2D(x: 300, y: 200),
                                    value: 5_000.0, secondaryValue: 10)
        XCTAssertEqual(resolvedResistance(of: dark) ?? -1, 5_000.0, accuracy: 1.0, "10 lux is the rating point")
        if let litR = resolvedResistance(of: lit), let darkR = resolvedResistance(of: dark) {
            XCTAssertLessThan(litR, darkR, "more lux means less resistance")
        }
    }

    private func resolvedResistance(of comp: CircuitComponent) -> Double? {
        let solver = MNASolver(circuit: Circuit(components: [comp], wires: []))
        return solver.resistance(of: comp)
    }

    // MARK: - Netlist export

    func testSPICEExportCoversInstrumentsAndDivider() {
        let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 100, y: 200), value: 12.0)
        let am = CircuitComponent(kind: .ammeter, designator: "A1", position: Point2D(x: 220, y: 200), value: 1e-3)
        let pot = CircuitComponent(kind: .potentiometer, designator: "RV1", position: Point2D(x: 340, y: 200),
                                   value: 10_000.0, secondaryValue: 0.5)
        let fuse = CircuitComponent(kind: .fuse, designator: "F1", position: Point2D(x: 460, y: 200),
                                    value: 0.05, secondaryValue: 2.0, stateBool: true)
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 540, y: 320))

        let circuit = Circuit(components: [v1, am, pot, fuse, gnd], wires: [
            Wire(startPinId: v1.pins[0].id, endPinId: am.pins[0].id),
            Wire(startPinId: am.pins[1].id, endPinId: pot.pins[0].id),
            Wire(startPinId: pot.pins[2].id, endPinId: fuse.pins[0].id),
            Wire(startPinId: fuse.pins[1].id, endPinId: gnd.pins[0].id),
            Wire(startPinId: pot.pins[1].id, endPinId: gnd.pins[0].id),
            Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
        ])

        let netlist = SPICEExporter.export(circuit: circuit, title: "Instruments")
        XCTAssertTrue(netlist.contains("A1"), "ammeter exports as its burden resistance")
        XCTAssertTrue(netlist.contains("RV1A") && netlist.contains("RV1B"), "the divider exports both track halves")
        XCTAssertTrue(netlist.contains("F1"))
        XCTAssertTrue(netlist.contains("fuse rated 2.0A"))
    }
}
