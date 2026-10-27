import Foundation

/// Thevenin and Norton equivalent circuit analyzer for B.Tech Year 1 Network Theorems.
public struct TheveninEquivalent {
    public let vTh: Double        // Thevenin Open-Circuit Voltage (Volts)
    public let rTh: Double        // Thevenin Equivalent Resistance (Ohms)
    public let iNorton: Double    // Norton Short-Circuit Current (Amps)
    public let pMax: Double       // Maximum Power Transfer = Vth^2 / (4 * Rth) (Watts)
}

public final class TheveninAnalyzer {
    /// Computes the Thevenin and Norton equivalent circuit seen between nodeA and nodeB.
    public static func computeEquivalent(circuit: Circuit, nodeA: Int, nodeB: Int) -> TheveninEquivalent? {
        guard nodeA != nodeB else { return nil }

        // 1. Solve circuit in open-circuit condition
        let openSolver = MNASolver(circuit: circuit, timeStep: 1e-4)
        let openRes = openSolver.step()
        let vaOpen = openRes.nodeVoltages[nodeA] ?? 0.0
        let vbOpen = openRes.nodeVoltages[nodeB] ?? 0.0
        let vTh = vaOpen - vbOpen

        // 2. Solve circuit with a small sense resistor (1e-6 ohm) between nodeA and nodeB to measure short-circuit current
        // Find pins corresponding to nodeA and nodeB
        let (pinMap, _) = circuit.resolveNodes()
        guard let pinAId = pinMap.first(where: { $0.value == nodeA })?.key,
              let pinBId = pinMap.first(where: { $0.value == nodeB })?.key else {
            return TheveninEquivalent(vTh: vTh, rTh: 0, iNorton: 0, pMax: 0)
        }

        // Add a 1 uOhm short-circuit test resistor
        let rShort = CircuitComponent(kind: .resistor, designator: "R_TEST", value: 1e-6)
        let wA = Wire(startPinId: pinAId, endPinId: rShort.pins[0].id)
        let wB = Wire(startPinId: rShort.pins[1].id, endPinId: pinBId)

        let shortCircuit = Circuit(
            components: circuit.components + [rShort],
            wires: circuit.wires + [wA, wB]
        )

        let shortSolver = MNASolver(circuit: shortCircuit, timeStep: 1e-4)
        _ = shortSolver.step()
        let iNorton = rShort.runtimeCurrent

        let rTh = abs(iNorton) > 1e-9 ? abs(vTh / iNorton) : 1e9
        let pMax = rTh > 1e-6 ? (vTh * vTh) / (4.0 * rTh) : 0.0

        return TheveninEquivalent(
            vTh: vTh,
            rTh: rTh,
            iNorton: iNorton,
            pMax: pMax
        )
    }
}
