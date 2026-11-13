import XCTest
@testable import MultiSimEngine

final class ValueEditingTests: XCTestCase {

    // MARK: - Parser

    func testParsesEngineeringSuffixes() {
        XCTAssertEqual(EngineeringUnitParser.parse("4.7k")!, 4700, accuracy: 1e-9)
        XCTAssertEqual(EngineeringUnitParser.parse("100u")!, 1e-4, accuracy: 1e-15)
        XCTAssertEqual(EngineeringUnitParser.parse("10MEG")!, 1e7, accuracy: 1e-3)
        XCTAssertEqual(EngineeringUnitParser.parse("1e-6")!, 1e-6, accuracy: 1e-18)
        XCTAssertEqual(EngineeringUnitParser.parse("-5", unit: "V")!, -5, accuracy: 1e-12)
    }

    func testParsesRKMNotation() {
        XCTAssertEqual(EngineeringUnitParser.parse("4k7")!, 4700, accuracy: 1e-9)
        XCTAssertEqual(EngineeringUnitParser.parse("2R2", unit: "Ω")!, 2.2, accuracy: 1e-12)
    }

    func testTrailingUnitIsNotMistakenForAPrefix() {
        XCTAssertEqual(EngineeringUnitParser.parse("100µF", unit: "F")!, 1e-4, accuracy: 1e-15)
        XCTAssertEqual(EngineeringUnitParser.parse("2.2 nF", unit: "F")!, 2.2e-9, accuracy: 1e-18)
        XCTAssertEqual(EngineeringUnitParser.parse("1kHz", unit: "Hz")!, 1000, accuracy: 1e-9)
        XCTAssertEqual(EngineeringUnitParser.parse("10mH", unit: "H")!, 0.01, accuracy: 1e-12)
        XCTAssertEqual(EngineeringUnitParser.parse("5mV", unit: "V")!, 0.005, accuracy: 1e-12)
        XCTAssertEqual(EngineeringUnitParser.parse("4.7kΩ", unit: "Ω")!, 4700, accuracy: 1e-9)
        XCTAssertEqual(EngineeringUnitParser.parse("4.7k ohm", unit: "Ω")!, 4700, accuracy: 1e-9)
        // M = mega, m = milli, even with the unit attached
        XCTAssertEqual(EngineeringUnitParser.parse("10MΩ", unit: "Ω")!, 1e7, accuracy: 1e-3)
        XCTAssertEqual(EngineeringUnitParser.parse("10mΩ", unit: "Ω")!, 0.01, accuracy: 1e-12)
    }

    func testRejectsGarbage() {
        for bad in ["abc", "", "   ", "1e400", "k", "4.7q"] {
            XCTAssertNil(EngineeringUnitParser.parse(bad), "\(bad) should not parse")
        }
        XCTAssertNil(EngineeringUnitParser.parse("V", unit: "V"))
    }

    func testFormatRoundTrips() {
        for v in [4700.0, 1e-6, 2.2e-9, 1e7, 0.01, 60.0, 1.5] {
            let text = EngineeringUnitParser.format(v)
            XCTAssertEqual(EngineeringUnitParser.parse(text)!, v, accuracy: abs(v) * 1e-3, "\(text)")
        }
    }

    // MARK: - E-series stepper

    func testE12Stepping() {
        XCTAssertEqual(ESeries.step(from: 1000, up: true), 1200, accuracy: 1e-9)
        XCTAssertEqual(ESeries.step(from: 1000, up: false), 820, accuracy: 1e-9)
        XCTAssertEqual(ESeries.step(from: 8200, up: true), 10_000, accuracy: 1e-9)
        XCTAssertEqual(ESeries.step(from: 1, up: false), 0.82, accuracy: 1e-12)
        XCTAssertEqual(ESeries.step(from: 1050, up: true), 1200, accuracy: 1e-9)   // off-series start
        XCTAssertEqual(ESeries.step(from: 1050, up: false), 1000, accuracy: 1e-9)
        XCTAssertEqual(ESeries.step(from: 1e-6, up: true), 1.2e-6, accuracy: 1e-15)
    }

    // MARK: - Ranges and specs

    func testEveryPartHasConsistentSpecs() {
        for kind in ComponentKind.allCases {
            for slot in [ParameterSlot.primary, .secondary] {
                guard let spec = kind.parameterSpec(slot) else { continue }
                XCTAssertTrue(spec.range.contains(spec.sliderRange.lowerBound), "\(kind) slider low outside range")
                XCTAssertTrue(spec.range.contains(spec.sliderRange.upperBound), "\(kind) slider high outside range")
                if spec.isLogarithmic { XCTAssertGreaterThan(spec.sliderRange.lowerBound, 0, "\(kind)") }
                XCTAssertTrue(spec.range.contains(spec.stepped(from: spec.sliderRange.lowerBound, up: true)), "\(kind)")
            }
        }
    }

    func testDefaultsAreInsideTheirOwnRanges() {
        for kind in ComponentKind.allCases {
            let d = kind.partDefaults
            if let s = kind.parameterSpec(.primary) {
                XCTAssertTrue(s.range.contains(d.value), "\(kind) default primary \(d.value) outside \(s.range)")
            }
            if let s = kind.parameterSpec(.secondary), d.secondaryValue != 0 {
                XCTAssertTrue(s.range.contains(d.secondaryValue), "\(kind) default secondary \(d.secondaryValue) outside \(s.range)")
            }
        }
    }

    func testClampingAndPolarity() {
        let r = ComponentKind.resistor.parameterSpec(.primary)!
        XCTAssertEqual(r.clamp(-50), r.range.lowerBound)          // resistance can never be negative
        let v = ComponentKind.dcVoltageSource.parameterSpec(.primary)!
        XCTAssertEqual(v.clamp(-12), -12)                          // but a supply can be reversed
        XCTAssertEqual(v.clamp(1e9), 1000)
        XCTAssertEqual(ComponentKind.acVoltageSource.parameterSpec(.primary)!.clamp(-3), 0)
    }

    func testLinearStepIsNice() {
        XCTAssertEqual(ComponentKind.dcVoltageSource.parameterSpec(.primary)!.linearStep, 1, accuracy: 1e-12)
        let up = ComponentKind.dcVoltageSource.parameterSpec(.primary)!.stepped(from: 5, up: true)
        XCTAssertEqual(up, 6, accuracy: 1e-12)
    }

    func testSampleWarningFlagsHighFrequencies() {
        let low = CircuitComponent(kind: .acVoltageSource, designator: "V1", value: 5, secondaryValue: 60)
        let high = CircuitComponent(kind: .acVoltageSource, designator: "V2", value: 10, secondaryValue: 1591)
        let dc = CircuitComponent(kind: .dcVoltageSource, designator: "V3", value: 5)
        XCTAssertNil(low.sampleWarning(timeStep: 1e-4))
        XCTAssertNotNil(high.sampleWarning(timeStep: 1e-4))
        XCTAssertNil(high.sampleWarning(timeStep: 1e-6))
        XCTAssertNil(dc.sampleWarning(timeStep: 1e-4))
    }

    // MARK: - Editing a value takes effect on the next solver step, no restart

    func testChangingResistanceMidRunChangesTheDivider() {
        let vsrc = CircuitComponent(kind: .dcVoltageSource, designator: "V1", value: 10)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", value: 1000)
        let r2 = CircuitComponent(kind: .resistor, designator: "R2", value: 1000)
        let gnd = CircuitComponent(kind: .ground, designator: "GND")
        let circuit = Circuit(
            components: [vsrc, r1, r2, gnd],
            wires: [
                Wire(startPinId: vsrc.pins[0].id, endPinId: r1.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id),
                Wire(startPinId: r2.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id)
            ]
        )
        let solver = MNASolver(circuit: circuit, timeStep: 1e-4)
        let mid = circuit.resolveNodes().pinToNode[r2.pins[0].id]!

        XCTAssertEqual(solver.step().nodeVoltages[mid]!, 5.0, accuracy: 1e-3)

        r2.value = 3000          // what the inspector does
        XCTAssertEqual(solver.step().nodeVoltages[mid]!, 7.5, accuracy: 1e-3)

        vsrc.value = -8          // reversed supply: 3k/(1k+3k) * -8 = -6
        XCTAssertEqual(solver.step().nodeVoltages[mid]!, -6.0, accuracy: 1e-3)
    }

    func testChangingCapacitanceChangesTheTimeConstant() {
        func voltageAfterOneTau(capacitance: Double) -> Double {
            let vsrc = CircuitComponent(kind: .dcVoltageSource, designator: "V1", value: 5)
            let r = CircuitComponent(kind: .resistor, designator: "R1", value: 1000)
            let c = CircuitComponent(kind: .capacitor, designator: "C1", value: capacitance)
            let gnd = CircuitComponent(kind: .ground, designator: "GND")
            let circuit = Circuit(
                components: [vsrc, r, c, gnd],
                wires: [
                    Wire(startPinId: vsrc.pins[0].id, endPinId: r.pins[0].id),
                    Wire(startPinId: r.pins[1].id, endPinId: c.pins[0].id),
                    Wire(startPinId: c.pins[1].id, endPinId: gnd.pins[0].id),
                    Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id)
                ]
            )
            let dt = 1e-6
            let solver = MNASolver(circuit: circuit, timeStep: dt)
            let steps = Int((1000.0 * capacitance) / dt)       // one tau = R*C
            for _ in 0..<steps { _ = solver.step() }
            return c.runtimePrevVoltage
        }
        // 1 - e^-1 = 63.2% of 5 V = 3.16 V, for any C, once time is measured in tau.
        XCTAssertEqual(voltageAfterOneTau(capacitance: 1e-6), 3.16, accuracy: 0.05)
        XCTAssertEqual(voltageAfterOneTau(capacitance: 4.7e-6), 3.16, accuracy: 0.05)
    }
}
