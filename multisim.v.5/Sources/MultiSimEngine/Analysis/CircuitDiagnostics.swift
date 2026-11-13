import Foundation

/// Comprehensive electrical diagnostic report for verifying circuit integrity and simulation state.
public struct CircuitDiagnosticReport {
    public let hasGround: Bool
    public let openPins: [(component: String, pin: String)]
    public let totalNodes: Int
    public let nodeVoltages: [Int: Double]
    public let branchCurrents: [(designator: String, current: Double, voltage: Double)]
    public let isClosedLoop: Bool
    public let statusMessage: String
    public let isHealthy: Bool
}

public final class CircuitDiagnostics {
    public static func diagnose(circuit: Circuit, solver: MNASolver) -> CircuitDiagnosticReport {
        let (_, nodeCount) = circuit.resolveNodes()

        // 1. Check for Ground reference (Node 0)
        let hasGround = circuit.components.contains { $0.kind == .ground }

        // 2. Check for unconnected / floating pins
        var openPins: [(component: String, pin: String)] = []
        let connectedPinIds = Set(circuit.wires.flatMap { [$0.startPinId, $0.endPinId] })

        for comp in circuit.components {
            // Ground only has 1 pin which must be connected
            for pin in comp.pins {
                if !connectedPinIds.contains(pin.id) {
                    openPins.append((component: comp.designator, pin: pin.name))
                }
            }
        }

        // 3. Current simulation results
        let currentStep = solver.step(dt: 1e-4)
        let voltages = currentStep.nodeVoltages

        var branches: [(designator: String, current: Double, voltage: Double)] = []
        var maxCurrent = 0.0

        for comp in circuit.components {
            let i = comp.runtimeCurrent
            let v = comp.runtimeVoltageDrop
            branches.append((designator: comp.designator, current: i, voltage: v))
            if abs(i) > maxCurrent {
                maxCurrent = abs(i)
            }
        }

        let isClosedLoop = maxCurrent > 1e-6
        let isHealthy = hasGround && openPins.isEmpty && isClosedLoop

        let statusMessage: String
        if !hasGround {
            statusMessage = "⚠️ Missing Ground: Add a Ground (0V) reference so node voltages can be calculated."
        } else if !openPins.isEmpty {
            statusMessage = "⚠️ Floating Pins Detected: \(openPins.count) unconnected terminal(s)."
        } else if !isClosedLoop {
            statusMessage = "ℹ️ Open Circuit: No current flowing through the circuit loop."
        } else {
            statusMessage = "✅ Circuit Verified: Closed loop active with balanced KVL/KCL."
        }

        return CircuitDiagnosticReport(
            hasGround: hasGround,
            openPins: openPins,
            totalNodes: nodeCount,
            nodeVoltages: voltages,
            branchCurrents: branches,
            isClosedLoop: isClosedLoop,
            statusMessage: statusMessage,
            isHealthy: isHealthy
        )
    }
}
