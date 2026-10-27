import Foundation

/// Result of a single simulation time step.
public struct SimulationStepResult {
    public let time: Double
    public let nodeVoltages: [Int: Double]
    public let converged: Bool
    public let iterations: Int
}

/// The core Modified Nodal Analysis (MNA) solver.
/// Solves both DC operating points and time-domain transient differential equations.
public final class MNASolver {
    public let circuit: Circuit
    public var currentTime: Double = 0.0
    public var timeStep: Double = 1e-4 // 100 microseconds default

    // Pin to Node mapping resolved from circuit graph
    public private(set) var pinToNode: [UUID: Int] = [:]
    public private(set) var totalNodes: Int = 0

    // Thermal voltage at 300K: kT/q
    private static let Vt = 0.02585
    private static let diodeIs = 1e-14

    public init(circuit: Circuit, timeStep: Double = 1e-4) {
        self.circuit = circuit
        self.timeStep = timeStep
        rebuildNetlist()
    }

    /// Rebuilds electrical nodes whenever components or wires are added, moved, or deleted.
    public func rebuildNetlist() {
        let resolution = circuit.resolveNodes()
        self.pinToNode = resolution.pinToNode
        self.totalNodes = resolution.totalNodes
    }

    /// Resets all internal component states (capacitors discharged, inductors zero current).
    public func reset() {
        currentTime = 0.0
        for comp in circuit.components {
            comp.runtimeVoltageDrop = 0.0
            comp.runtimeCurrent = 0.0
            comp.runtimePrevVoltage = 0.0
            comp.runtimePrevCurrent = 0.0
        }
        for i in 0..<circuit.wires.count {
            circuit.wires[i].runtimeCurrent = 0.0
        }
    }

    /// Steps the simulation forward by `dt` seconds using Newton-Raphson iteration.
    public func step(dt: Double? = nil) -> SimulationStepResult {
        let h = dt ?? timeStep
        currentTime += h

        // If no nodes, return empty result
        if totalNodes == 0 {
            return SimulationStepResult(time: currentTime, nodeVoltages: [0: 0.0], converged: true, iterations: 0)
        }

        // Identify voltage sources / constraints that require auxiliary MNA variables
        var voltageSourceComps: [(comp: CircuitComponent, nPlus: Int, nMinus: Int, targetV: Double)] = []
        var vcvsComps: [(comp: CircuitComponent, nOutPlus: Int, nOutMinus: Int, nCtrlPlus: Int, nCtrlMinus: Int, gain: Double)] = []

        for comp in circuit.components {
            let n = nodeIndices(for: comp)
            switch comp.kind {
            case .dcVoltageSource:
                let v = comp.value
                voltageSourceComps.append((comp, n[0], n[1], v))
            case .acVoltageSource:
                // v(t) = V_offset + Amplitude * sin(2*pi*f*t + phase)
                let amplitude = comp.value
                let freq = comp.secondaryValue > 0 ? comp.secondaryValue : 60.0
                let v = amplitude * sin(2.0 * .pi * freq * currentTime)
                voltageSourceComps.append((comp, n[0], n[1], v))
            case .clockSource:
                let amplitude = comp.value
                let freq = comp.secondaryValue > 0 ? comp.secondaryValue : 1000.0
                let period = 1.0 / freq
                let phaseInPeriod = currentTime.truncatingRemainder(dividingBy: period)
                let v = phaseInPeriod < (period * 0.5) ? amplitude : 0.0
                voltageSourceComps.append((comp, n[0], n[1], v))
            case .vcvs:
                let gain = comp.value
                let nOutP = n.count > 0 ? n[0] : 0
                let nOutM = n.count > 1 ? n[1] : 0
                let nCtrlP = n.count > 2 ? n[2] : 0
                let nCtrlM = n.count > 3 ? n[3] : 0
                vcvsComps.append((comp, nOutP, nOutM, nCtrlP, nCtrlM, gain))
            case .opAmp:
                // Output pin (pin 2) forced relative to Ground: V_out = clamp(A_OL * (V+ - V-), -15, 15)
                // Modeled as a voltage source on the output pin
                let vPlus = nodeVoltage(n[1])
                let vMinus = nodeVoltage(n[0])
                let diff = vPlus - vMinus
                let aol = 1e5
                let targetV = min(max(diff * aol, -15.0), 15.0)
                voltageSourceComps.append((comp, n[2], 0, targetV))
            case .logicAND, .logicOR, .logicNAND, .logicNOR, .logicXOR, .logicNOT:
                // Digital gates output 5.0V (High) or 0.0V (Low) with 50 ohm output resistance
                let targetV = evaluateLogicGate(comp: comp, nodes: n)
                voltageSourceComps.append((comp, n.last ?? 0, 0, targetV))
            default:
                break
            }
        }

        let numAux = voltageSourceComps.count + vcvsComps.count
        let matrixSize = totalNodes + numAux

        var currentVoltages = [Int: Double]()
        currentVoltages[0] = 0.0
        for i in 1...totalNodes {
            currentVoltages[i] = 0.0
        }

        // Newton-Raphson loop for non-linear components
        var converged = false
        var iterations = 0
        let maxIterations = 25
        let tolerance = 1e-4

        while !converged && iterations < maxIterations {
            iterations += 1

            var A = Matrix(rows: matrixSize, cols: matrixSize)
            var b = [Double](repeating: 0.0, count: matrixSize)

            // 1. Stamp linear passives and companion models
            for comp in circuit.components {
                let n = nodeIndices(for: comp)
                switch comp.kind {
                case .resistor:
                    let r = max(comp.value, 1e-6)
                    let g = 1.0 / r
                    stampConductance(matrix: &A, n1: n[0], n2: n[1], g: g)

                case .potentiometer:
                    // Resistance slider (value * ratio)
                    let ratio = min(max(comp.secondaryValue > 0 ? comp.secondaryValue : 0.5, 0.001), 0.999)
                    let r = max(comp.value * ratio, 1e-6)
                    let g = 1.0 / r
                    stampConductance(matrix: &A, n1: n[0], n2: n[1], g: g)

                case .switchSPST:
                    // If closed: 1e-4 ohm. If open: 1e9 ohm
                    let r = comp.stateBool ? 1e-4 : 1e9
                    let g = 1.0 / r
                    stampConductance(matrix: &A, n1: n[0], n2: n[1], g: g)

                case .capacitor:
                    // Backward Euler companion model:
                    // G_eq = C / dt
                    // I_eq = (C / dt) * V_prev
                    let c = max(comp.value, 1e-15)
                    let geq = c / h
                    let ieq = geq * comp.runtimePrevVoltage
                    stampConductance(matrix: &A, n1: n[0], n2: n[1], g: geq)
                    stampCurrentSource(b: &b, fromNode: n[1], toNode: n[0], current: ieq)

                case .inductor:
                    // Backward Euler companion model:
                    // G_eq = dt / L
                    // I_eq = I_prev
                    let l = max(comp.value, 1e-12)
                    let geq = h / l
                    let ieq = comp.runtimePrevCurrent
                    stampConductance(matrix: &A, n1: n[0], n2: n[1], g: geq)
                    stampCurrentSource(b: &b, fromNode: n[0], toNode: n[1], current: ieq)

                case .dcCurrentSource:
                    let i = comp.value
                    stampCurrentSource(b: &b, fromNode: n[0], toNode: n[1], current: i)

                case .diode, .led:
                    // Non-linear diode with Newton-Raphson linearization
                    let nA = n[0]
                    let nK = n[1]
                    let vA = currentVoltages[nA] ?? 0.0
                    let vK = currentVoltages[nK] ?? 0.0
                    var vd = vA - vK

                    let isSat = comp.kind == .led ? 1e-18 : Self.diodeIs
                    let nCoeff = comp.kind == .led ? 2.0 : 1.0
                    let vt = Self.Vt * nCoeff

                    // Initial guess on first iteration if near zero
                    if iterations == 1 && vd < 0.1 && comp.runtimePrevVoltage < 0.1 {
                        vd = comp.kind == .led ? (comp.ledColor.forwardVoltage * 0.8) : 0.6
                    } else if iterations == 1 && comp.runtimePrevVoltage >= 0.1 {
                        vd = comp.runtimePrevVoltage
                    }

                    // Clamp to realistic forward drop range
                    let maxVd = comp.kind == .led ? (comp.ledColor.forwardVoltage + 0.3) : 0.82
                    vd = min(max(vd, -5.0), maxVd)

                    let expTerm = exp(vd / vt)
                    let id = isSat * (expTerm - 1.0)
                    let gd = max((isSat / vt) * expTerm, 1e-12)
                    let ieq = id - gd * vd

                    stampConductance(matrix: &A, n1: nA, n2: nK, g: gd)
                    stampCurrentSource(b: &b, fromNode: nA, toNode: nK, current: ieq)

                case .zenerDiode:
                    // Forward diode + reverse zener breakdown
                    let nA = n[0]
                    let nK = n[1]
                    let vd = (currentVoltages[nA] ?? 0.0) - (currentVoltages[nK] ?? 0.0)
                    let vz = comp.secondaryValue > 0 ? comp.secondaryValue : 5.1

                    if vd < -vz {
                        // In reverse zener breakdown
                        let gz = 1.0 / 10.0 // 10 ohm zener impedance
                        stampConductance(matrix: &A, n1: nA, n2: nK, g: gz)
                        let iz = -gz * (-vd - vz)
                        stampCurrentSource(b: &b, fromNode: nA, toNode: nK, current: iz)
                    } else {
                        // Standard diode behavior
                        let gd = vd > 0.6 ? 1.0 / 0.1 : 1e-12
                        stampConductance(matrix: &A, n1: nA, n2: nK, g: gd)
                    }

                case .bjtNPN:
                    // Base: n[0], Collector: n[1], Emitter: n[2]
                    let nB = n[0], nC = n[1], nE = n[2]
                    let vB = currentVoltages[nB] ?? 0.0
                    let vE = currentVoltages[nE] ?? 0.0
                    let vBE = min(max(vB - vE, -5.0), 0.8)
                    let beta = comp.secondaryValue > 0 ? comp.secondaryValue : 100.0

                    // Base-Emitter diode
                    let ib = 1e-14 * (exp(vBE / Self.Vt) - 1.0)
                    let gbe = max((1e-14 / Self.Vt) * exp(vBE / Self.Vt), 1e-12)
                    stampConductance(matrix: &A, n1: nB, n2: nE, g: gbe)
                    stampCurrentSource(b: &b, fromNode: nB, toNode: nE, current: ib - gbe * vBE)

                    // Collector current: Ic = beta * Ib
                    let ic = max(beta * ib, 0.0)
                    stampCurrentSource(b: &b, fromNode: nC, toNode: nE, current: ic)

                case .bjtPNP:
                    let nB = n[0], nC = n[1], nE = n[2]
                    let vB = currentVoltages[nB] ?? 0.0
                    let vE = currentVoltages[nE] ?? 0.0
                    let vEB = min(max(vE - vB, -5.0), 0.8)
                    let beta = comp.secondaryValue > 0 ? comp.secondaryValue : 100.0

                    let ib = 1e-14 * (exp(vEB / Self.Vt) - 1.0)
                    let geb = max((1e-14 / Self.Vt) * exp(vEB / Self.Vt), 1e-12)
                    stampConductance(matrix: &A, n1: nE, n2: nB, g: geb)
                    stampCurrentSource(b: &b, fromNode: nE, toNode: nB, current: ib - geb * vEB)

                    let ic = max(beta * ib, 0.0)
                    stampCurrentSource(b: &b, fromNode: nE, toNode: nC, current: ic)

                case .vccs:
                    // Voltage-Controlled Current Source: I = gm * (V_ctrl+ - V_ctrl-)
                    let gm = comp.value
                    let nOutP = n.count > 0 ? n[0] : 0
                    let nOutM = n.count > 1 ? n[1] : 0
                    let nCtrlP = n.count > 2 ? n[2] : 0
                    let nCtrlM = n.count > 3 ? n[3] : 0

                    if nOutP > 0 && nCtrlP > 0 { A[nOutP - 1, nCtrlP - 1] += gm }
                    if nOutP > 0 && nCtrlM > 0 { A[nOutP - 1, nCtrlM - 1] -= gm }
                    if nOutM > 0 && nCtrlP > 0 { A[nOutM - 1, nCtrlP - 1] -= gm }
                    if nOutM > 0 && nCtrlM > 0 { A[nOutM - 1, nCtrlM - 1] += gm }

                default:
                    break
                }
            }

            // 2. Stamp auxiliary voltage source equations
            for (k, vsrc) in voltageSourceComps.enumerated() {
                let eqRow = totalNodes + k
                let nPlus = vsrc.nPlus
                let nMinus = vsrc.nMinus

                if nPlus > 0 {
                    A[nPlus - 1, eqRow] += 1.0
                    A[eqRow, nPlus - 1] += 1.0
                }
                if nMinus > 0 {
                    A[nMinus - 1, eqRow] -= 1.0
                    A[eqRow, nMinus - 1] -= 1.0
                }
                b[eqRow] = vsrc.targetV
            }

            // 2b. Stamp VCVS auxiliary equations: V(out+) - V(out-) - gain * (V(ctrl+) - V(ctrl-)) = 0
            for (k, vcvs) in vcvsComps.enumerated() {
                let eqRow = totalNodes + voltageSourceComps.count + k
                if vcvs.nOutPlus > 0 {
                    A[vcvs.nOutPlus - 1, eqRow] += 1.0
                    A[eqRow, vcvs.nOutPlus - 1] += 1.0
                }
                if vcvs.nOutMinus > 0 {
                    A[vcvs.nOutMinus - 1, eqRow] -= 1.0
                    A[eqRow, vcvs.nOutMinus - 1] -= 1.0
                }
                if vcvs.nCtrlPlus > 0 {
                    A[eqRow, vcvs.nCtrlPlus - 1] -= vcvs.gain
                }
                if vcvs.nCtrlMinus > 0 {
                    A[eqRow, vcvs.nCtrlMinus - 1] += vcvs.gain
                }
                b[eqRow] = 0.0
            }

            // 3. Solve system A * x = b
            guard let solution = A.solve(b: b) else {
                // Singular matrix (floating node or short-circuit loop)
                break
            }

            // 4. Update voltages & check convergence
            var maxDelta = 0.0
            for i in 1...totalNodes {
                let newV = solution[i - 1]
                let oldV = currentVoltages[i] ?? 0.0
                let delta = abs(newV - oldV)
                if delta > maxDelta {
                    maxDelta = delta
                }
                currentVoltages[i] = newV
            }

            if maxDelta < tolerance {
                converged = true
            }
        }

        // 5. Update runtime component states (currents, voltages, companion history)
        updateComponentRuntimeStates(voltages: currentVoltages, dt: h)

        return SimulationStepResult(
            time: currentTime,
            nodeVoltages: currentVoltages,
            converged: converged,
            iterations: iterations
        )
    }

    // MARK: - Helper Methods

    private func nodeIndices(for comp: CircuitComponent) -> [Int] {
        comp.pins.map { pinToNode[$0.id] ?? 0 }
    }

    private func nodeVoltage(_ nodeIndex: Int) -> Double {
        if nodeIndex == 0 { return 0.0 }
        // Default to 0.0 if not yet solved
        return 0.0
    }

    private func stampConductance(matrix: inout Matrix, n1: Int, n2: Int, g: Double) {
        if n1 > 0 {
            matrix[n1 - 1, n1 - 1] += g
        }
        if n2 > 0 {
            matrix[n2 - 1, n2 - 1] += g
        }
        if n1 > 0 && n2 > 0 {
            matrix[n1 - 1, n2 - 1] -= g
            matrix[n2 - 1, n1 - 1] -= g
        }
    }

    private func stampCurrentSource(b: inout [Double], fromNode: Int, toNode: Int, current: Double) {
        if fromNode > 0 {
            b[fromNode - 1] -= current
        }
        if toNode > 0 {
            b[toNode - 1] += current
        }
    }

    private func evaluateLogicGate(comp: CircuitComponent, nodes: [Int]) -> Double {
        // High = 5.0V, Low = 0.0V. Threshold = 2.5V
        let in1High = nodeVoltage(nodes[0]) > 2.5
        let in2High = nodes.count > 1 ? (nodeVoltage(nodes[1]) > 2.5) : false

        let result: Bool
        switch comp.kind {
        case .logicAND: result = in1High && in2High
        case .logicOR: result = in1High || in2High
        case .logicNAND: result = !(in1High && in2High)
        case .logicNOR: result = !(in1High || in2High)
        case .logicXOR: result = in1High != in2High
        case .logicNOT: result = !in1High
        default: result = false
        }
        return result ? 5.0 : 0.0
    }

    private func updateComponentRuntimeStates(voltages: [Int: Double], dt: Double) {
        for comp in circuit.components {
            let n = nodeIndices(for: comp)
            let v0 = voltages[n[0]] ?? 0.0
            let v1 = n.count > 1 ? (voltages[n[1]] ?? 0.0) : 0.0
            let vDrop = v0 - v1
            comp.runtimeVoltageDrop = vDrop

            switch comp.kind {
            case .resistor, .switchSPST, .potentiometer:
                let r: Double
                if comp.kind == .switchSPST {
                    r = comp.stateBool ? 1e-4 : 1e9
                } else if comp.kind == .potentiometer {
                    let ratio = min(max(comp.secondaryValue > 0 ? comp.secondaryValue : 0.5, 0.001), 0.999)
                    r = max(comp.value * ratio, 1e-6)
                } else {
                    r = max(comp.value, 1e-6)
                }
                comp.runtimeCurrent = vDrop / r

            case .capacitor:
                // i = C * (v - v_prev) / dt
                let c = max(comp.value, 1e-15)
                comp.runtimeCurrent = c * (vDrop - comp.runtimePrevVoltage) / dt
                comp.runtimePrevVoltage = vDrop

            case .inductor:
                // i = i_prev + (v * dt / L)
                let l = max(comp.value, 1e-12)
                let newI = comp.runtimePrevCurrent + (vDrop * dt / l)
                comp.runtimeCurrent = newI
                comp.runtimePrevCurrent = newI

            case .diode, .led:
                let isSat = comp.kind == .led ? 1e-18 : Self.diodeIs
                let nCoeff = comp.kind == .led ? 2.0 : 1.0
                let vt = Self.Vt * nCoeff
                let clampedVd = min(max(vDrop, -10.0), 1.5)
                comp.runtimeCurrent = isSat * (exp(clampedVd / vt) - 1.0)
                comp.runtimePrevVoltage = vDrop

            default:
                break
            }
        }

        // Update runtime current on wires for visual animation
        for i in 0..<circuit.wires.count {
            let wire = circuit.wires[i]
            // Wire current matches connected component pin current
            if let comp = circuit.components.first(where: { c in c.pins.contains { $0.id == wire.startPinId } }) {
                circuit.wires[i].runtimeCurrent = comp.runtimeCurrent
            }
        }
    }
}
