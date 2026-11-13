import Foundation

/// Result of a single simulation time step.
public struct SimulationStepResult {
    public let time: Double
    public let nodeVoltages: [Int: Double]
    public let converged: Bool
    public let iterations: Int
    /// True when the MNA matrix could not be factored (floating node or a source shorted across itself).
    public let isSingular: Bool
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
    /// True when the last solve produced a usable operating point.
    public private(set) var isSolutionValid = false

    // Thermal voltage at 300K: kT/q
    private static let Vt = 0.02585
    private static let diodeIs = 1e-14

    // Instrument / switch modelling constants
    static let idealAmmeterResistance = 1e-3
    static let idealVoltmeterResistance = 1e7
    static let openCircuitResistance = 1e9
    static let closedContactResistance = 1e-4
    static let ohmmeterTestCurrent = 1e-3
    static let thermistorBeta = 3950.0
    private static let thermistorReferenceKelvin = 298.15 // 25 C

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
        isSolutionValid = false
        for comp in circuit.components {
            comp.runtimeVoltageDrop = 0.0
            comp.runtimeCurrent = 0.0
            comp.runtimePrevVoltage = 0.0
            comp.runtimePrevCurrent = 0.0
            comp.runtimeReading = 0.0
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
            return SimulationStepResult(time: currentTime, nodeVoltages: [0: 0.0], converged: true, iterations: 0, isSingular: false)
        }

        // Auxiliary MNA variables are structural: every voltage-source-like part adds one row/column.
        let auxCount = circuit.components.reduce(0) { $0 + Self.auxiliaryRowCount(for: $1) }
        let matrixSize = totalNodes + auxCount

        var currentVoltages = [Int: Double]()
        currentVoltages[0] = 0.0
        for i in 1...totalNodes {
            currentVoltages[i] = 0.0
        }

        var converged = false
        var singular = false
        var iterations = 0
        let maxIterations = 25
        let tolerance = 1e-4

        while !converged && iterations < maxIterations {
            iterations += 1

            var A = Matrix(rows: matrixSize, cols: matrixSize)
            var b = [Double](repeating: 0.0, count: matrixSize)

            // 1. Stamp linear passives and companion models
            for comp in circuit.components {
                stampPassive(comp, nodes: nodeIndices(for: comp), into: &A, rhs: &b, voltages: currentVoltages, dt: h)
            }

            // 2. Stamp sources and constraints. Targets are recomputed every pass so that
            //    dependent parts (op-amp, logic gates) see the voltages from the previous iterate.
            var auxRow = totalNodes
            for comp in circuit.components {
                guard Self.auxiliaryRowCount(for: comp) > 0 else { continue }
                let n = nodeIndices(for: comp)
                stampAuxiliary(comp, nodes: n, row: auxRow, into: &A, rhs: &b, voltages: currentVoltages, time: currentTime)
                auxRow += 1
            }

            // 3. Solve system A * x = b
            guard let solution = A.solve(b: b) else {
                // Singular matrix (floating node or short-circuit loop)
                singular = true
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

        isSolutionValid = !singular

        // 5. Update runtime component states (currents, voltages, companion history, instrument readings)
        updateComponentRuntimeStates(voltages: currentVoltages, dt: h)

        return SimulationStepResult(
            time: currentTime,
            nodeVoltages: currentVoltages,
            converged: converged,
            iterations: iterations,
            isSingular: singular
        )
    }

    // MARK: - Node helpers

    private func nodeIndices(for comp: CircuitComponent) -> [Int] {
        comp.pins.map { pinToNode[$0.id] ?? 0 }
    }

    private func voltage(of node: Int, in voltages: [Int: Double]) -> Double {
        if node == 0 { return 0.0 }
        return voltages[node] ?? 0.0
    }

    /// How many auxiliary MNA variables a part needs (1 for each ideal source / constraint).
    static func auxiliaryRowCount(for comp: CircuitComponent) -> Int {
        switch comp.kind {
        case .dcVoltageSource, .acVoltageSource, .clockSource, .functionGenerator, .opAmp, .vcvs:
            return 1
        case .logicAND, .logicOR, .logicNOT, .logicNAND, .logicNOR, .logicXOR, .logicXNOR, .logicBuffer:
            return 1
        default:
            return 0
        }
    }

    // MARK: - Passive stamping

    private func stampPassive(
        _ comp: CircuitComponent,
        nodes n: [Int],
        into A: inout Matrix,
        rhs b: inout [Double],
        voltages: [Int: Double],
        dt h: Double
    ) {
        func node(_ i: Int) -> Int { i < n.count ? n[i] : 0 }

        switch comp.kind {
        case .resistor, .switchSPST, .rheostat, .lamp, .fuse, .thermistor, .photoResistor,
             .ammeter, .voltmeter, .galvanometer:
            if let r = resistance(of: comp) {
                stampConductance(matrix: &A, n1: node(0), n2: node(1), g: 1.0 / r)
            }

        case .multimeter:
            switch MeterMode(rawValue: comp.modeIndex) ?? .voltage {
            case .voltage, .current:
                let r = multimeterResistance(comp)
                stampConductance(matrix: &A, n1: node(0), n2: node(1), g: 1.0 / r)
            case .resistance:
                // Ohmmeter: forces a known test current through whatever is hooked across it.
                stampCurrentSource(b: &b, fromNode: node(1), toNode: node(0), current: ohmmeterTestCurrent(for: comp))
            }

        case .ohmmeter:
            stampCurrentSource(b: &b, fromNode: node(1), toNode: node(0), current: ohmmeterTestCurrent(for: comp))

        case .potentiometer:
            let total = max(comp.value, 1e-6)
            let ratio = Self.wiperRatio(of: comp)
            guard n.count >= 3 else {
                // Files saved before the 3-terminal divider: behave as a variable resistor.
                stampConductance(matrix: &A, n1: node(0), n2: node(1), g: 1.0 / max(total * ratio, 1e-6))
                return
            }
            // Track split at the wiper: A-W and W-B resistors.
            stampConductance(matrix: &A, n1: node(0), n2: node(2), g: 1.0 / max(total * ratio, 1e-6))
            stampConductance(matrix: &A, n1: node(2), n2: node(1), g: 1.0 / max(total * (1.0 - ratio), 1e-6))

        case .wattmeter:
            // Current coil in series (pin 0 -> 1), pressure coil across the load (pin 2 -> 3).
            stampConductance(matrix: &A, n1: node(0), n2: node(1), g: 1.0 / max(comp.value > 0 ? comp.value : 0.05, 1e-4))
            let pcR = comp.secondaryValue > 0 ? comp.secondaryValue : 1e6
            stampConductance(matrix: &A, n1: node(2), n2: node(3), g: 1.0 / pcR)

        case .capacitor, .electrolyticCapacitor, .trimmerCapacitor:
            // Backward Euler companion model: G = C/dt in parallel with a history source.
            let c = max(comp.value, 1e-15)
            let geq = c / h
            let ieq = geq * comp.runtimePrevVoltage
            stampConductance(matrix: &A, n1: node(0), n2: node(1), g: geq)
            stampCurrentSource(b: &b, fromNode: node(1), toNode: node(0), current: ieq)

        case .inductor:
            // Backward Euler companion model: G = dt/L in parallel with a history source.
            let l = max(comp.value, 1e-12)
            let geq = h / l
            let ieq = comp.runtimePrevCurrent
            stampConductance(matrix: &A, n1: node(0), n2: node(1), g: geq)
            stampCurrentSource(b: &b, fromNode: node(0), toNode: node(1), current: ieq)

        case .dcCurrentSource:
            stampCurrentSource(b: &b, fromNode: node(0), toNode: node(1), current: comp.value)

        case .diode, .led, .schottkyDiode:
            stampJunction(comp, anode: node(0), cathode: node(1), into: &A, rhs: &b, voltages: voltages)

        case .zenerDiode:
            let nA = node(0)
            let nK = node(1)
            let vd = voltage(of: nA, in: voltages) - voltage(of: nK, in: voltages)
            let vz = comp.secondaryValue > 0 ? comp.secondaryValue : 5.1

            if vd < -vz {
                // Reverse breakdown: modelled as a 10 ohm impedance clamped at Vz.
                let gz = 1.0 / 10.0
                stampConductance(matrix: &A, n1: nA, n2: nK, g: gz)
                stampCurrentSource(b: &b, fromNode: nA, toNode: nK, current: -gz * (-vd - vz))
            } else if vd > 0.6 {
                stampConductance(matrix: &A, n1: nA, n2: nK, g: 1.0 / 0.1)
            } else {
                stampConductance(matrix: &A, n1: nA, n2: nK, g: 1e-12)
            }

        case .bjtNPN, .bjtPNP:
            stampBJT(comp, nodes: [node(0), node(1), node(2)], into: &A, rhs: &b, voltages: voltages, pnp: comp.kind == .bjtPNP)

        case .vccs:
            // Voltage-Controlled Current Source: I = gm * (V_ctrl+ - V_ctrl-)
            let gm = comp.value
            let nOutP = node(0), nOutM = node(1), nCtrlP = node(2), nCtrlM = node(3)

            if nOutP > 0, nCtrlP > 0 { A[nOutP - 1, nCtrlP - 1] += gm }
            if nOutP > 0, nCtrlM > 0 { A[nOutP - 1, nCtrlM - 1] -= gm }
            if nOutM > 0, nCtrlP > 0 { A[nOutM - 1, nCtrlP - 1] -= gm }
            if nOutM > 0, nCtrlM > 0 { A[nOutM - 1, nCtrlM - 1] += gm }

        default:
            break
        }
    }

    /// Instantaneous target value for an independent source.
    private func sourceTargetVoltage(_ comp: CircuitComponent, time t: Double) -> Double {
        switch comp.kind {
        case .dcVoltageSource:
            return comp.value
        case .acVoltageSource:
            let freq = comp.secondaryValue > 0 ? comp.secondaryValue : 60.0
            return comp.value * sin(2.0 * .pi * freq * t)
        case .clockSource:
            let freq = comp.secondaryValue > 0 ? comp.secondaryValue : 1000.0
            let period = 1.0 / freq
            return t.truncatingRemainder(dividingBy: period) < period * 0.5 ? comp.value : 0.0
        case .functionGenerator:
            let freq = comp.secondaryValue > 0 ? comp.secondaryValue : 1000.0
            let phase = (t * freq).truncatingRemainder(dividingBy: 1.0)
            switch GeneratorWaveform(rawValue: comp.modeIndex) ?? .sine {
            case .sine:
                return comp.value * sin(2.0 * .pi * phase)
            case .square:
                return phase < 0.5 ? comp.value : -comp.value
            case .triangle:
                // phase 0 -> +V, 0.5 -> -V, 1 -> +V
                let p = phase < 0.5 ? phase * 2.0 : (phase - 0.5) * 2.0
                return comp.value * (p < 0.5 ? (4.0 * p - 1.0) : (3.0 - 4.0 * p))
            }
        default:
            return 0.0
        }
    }

    private func stampAuxiliary(
        _ comp: CircuitComponent,
        nodes n: [Int],
        row eqRow: Int,
        into A: inout Matrix,
        rhs b: inout [Double],
        voltages: [Int: Double],
        time t: Double
    ) {
        func node(_ i: Int) -> Int { i < n.count ? n[i] : 0 }

        func stampIdealSource(nPlus: Int, nMinus: Int, target: Double) {
            if nPlus > 0 {
                A[nPlus - 1, eqRow] += 1.0
                A[eqRow, nPlus - 1] += 1.0
            }
            if nMinus > 0 {
                A[nMinus - 1, eqRow] -= 1.0
                A[eqRow, nMinus - 1] -= 1.0
            }
            b[eqRow] = target
        }

        switch comp.kind {
        case .dcVoltageSource, .acVoltageSource, .clockSource, .functionGenerator:
            stampIdealSource(nPlus: node(0), nMinus: node(1), target: sourceTargetVoltage(comp, time: t))

        case .vcvs:
            // V(out+) - V(out-) = gain * (V(ctrl+) - V(ctrl-))
            let gain = comp.value
            let nOutP = node(0), nOutM = node(1), nCtrlP = node(2), nCtrlM = node(3)
            if nOutP > 0 {
                A[nOutP - 1, eqRow] += 1.0
                A[eqRow, nOutP - 1] += 1.0
            }
            if nOutM > 0 {
                A[nOutM - 1, eqRow] -= 1.0
                A[eqRow, nOutM - 1] -= 1.0
            }
            if nCtrlP > 0 { A[eqRow, nCtrlP - 1] -= gain }
            if nCtrlM > 0 { A[eqRow, nCtrlM - 1] += gain }
            b[eqRow] = 0.0

        case .opAmp:
            // Macro-model: output pin driven as a source against ground with finite open-loop gain and rails.
            let vPlus = voltage(of: node(1), in: voltages)
            let vMinus = voltage(of: node(0), in: voltages)
            let rail = comp.secondaryValue > 0 ? comp.secondaryValue : 15.0
            let target = min(max((vPlus - vMinus) * 1e5, -rail), rail)
            stampIdealSource(nPlus: node(2), nMinus: 0, target: target)

        case .logicAND, .logicOR, .logicNOT, .logicNAND, .logicNOR, .logicXOR, .logicXNOR, .logicBuffer:
            stampIdealSource(nPlus: n.last ?? 0, nMinus: 0, target: evaluateLogicGate(comp: comp, nodes: n, voltages: voltages))

        default:
            break
        }
    }

    // MARK: - Device models

    private struct JunctionModel {
        let saturation: Double
        let emissionCoefficient: Double
        let maxForwardVoltage: Double
    }

    private static func junctionModel(for comp: CircuitComponent) -> JunctionModel {
        switch comp.kind {
        case .led:
            return JunctionModel(saturation: 1e-18, emissionCoefficient: 2.0, maxForwardVoltage: comp.ledColor.forwardVoltage + 0.3)
        case .schottkyDiode:
            return JunctionModel(saturation: 1e-12, emissionCoefficient: 1.0, maxForwardVoltage: 0.45)
        default:
            return JunctionModel(saturation: diodeIs, emissionCoefficient: 1.0, maxForwardVoltage: 0.82)
        }
    }

    /// Newton-Raphson linearisation of a PN junction (diode / LED / Schottky).
    private func stampJunction(
        _ comp: CircuitComponent,
        anode nA: Int,
        cathode nK: Int,
        into A: inout Matrix,
        rhs b: inout [Double],
        voltages: [Int: Double]
    ) {
        let model = Self.junctionModel(for: comp)
        let vt = Self.Vt * model.emissionCoefficient

        var vd = voltage(of: nA, in: voltages) - voltage(of: nK, in: voltages)

        // Seed the first iterate near the conduction knee so the exponential does not start at zero.
        if comp.runtimePrevVoltage >= 0.1 {
            vd = comp.runtimePrevVoltage
        } else if vd < 0.1 {
            vd = (model.maxForwardVoltage - 0.3) * 0.85
        }
        vd = min(max(vd, -5.0), model.maxForwardVoltage)

        let expTerm = exp(vd / vt)
        let id = model.saturation * (expTerm - 1.0)
        let gd = max((model.saturation / vt) * expTerm, 1e-12)

        stampConductance(matrix: &A, n1: nA, n2: nK, g: gd)
        stampCurrentSource(b: &b, fromNode: nA, toNode: nK, current: id - gd * vd)
    }

    private func stampBJT(
        _ comp: CircuitComponent,
        nodes n: [Int],
        into A: inout Matrix,
        rhs b: inout [Double],
        voltages: [Int: Double],
        pnp: Bool
    ) {
        guard n.count >= 3 else { return }
        let nB = n[0], nC = n[1], nE = n[2]
        let beta = comp.secondaryValue > 0 ? comp.secondaryValue : 100.0
        let vB = voltage(of: nB, in: voltages)
        let vE = voltage(of: nE, in: voltages)

        if pnp {
            let vEB = min(max(vE - vB, -5.0), 0.8)
            let ib = 1e-14 * (exp(vEB / Self.Vt) - 1.0)
            let geb = max((1e-14 / Self.Vt) * exp(vEB / Self.Vt), 1e-12)
            stampConductance(matrix: &A, n1: nE, n2: nB, g: geb)
            stampCurrentSource(b: &b, fromNode: nE, toNode: nB, current: ib - geb * vEB)
            stampCurrentSource(b: &b, fromNode: nE, toNode: nC, current: max(beta * ib, 0.0))
        } else {
            let vBE = min(max(vB - vE, -5.0), 0.8)
            let ib = 1e-14 * (exp(vBE / Self.Vt) - 1.0)
            let gbe = max((1e-14 / Self.Vt) * exp(vBE / Self.Vt), 1e-12)
            stampConductance(matrix: &A, n1: nB, n2: nE, g: gbe)
            stampCurrentSource(b: &b, fromNode: nB, toNode: nE, current: ib - gbe * vBE)
            stampCurrentSource(b: &b, fromNode: nC, toNode: nE, current: max(beta * ib, 0.0))
        }
    }

    // MARK: - Parameter resolution

    /// Wiper position as a 0...1 fraction.
    public static func wiperRatio(of comp: CircuitComponent) -> Double {
        guard comp.secondaryValue > 0 else { return 0.5 }
        return min(max(comp.secondaryValue, 0.001), 0.999)
    }

    private func multimeterResistance(_ comp: CircuitComponent) -> Double {
        switch MeterMode(rawValue: comp.modeIndex) ?? .voltage {
        case .voltage: return comp.value > 0 ? comp.value : Self.idealVoltmeterResistance
        case .current: return comp.value > 0 ? max(comp.value, 1e-6) : Self.idealAmmeterResistance
        case .resistance: return Self.openCircuitResistance
        }
    }

    private func ohmmeterTestCurrent(for comp: CircuitComponent) -> Double {
        comp.value > 0 ? comp.value : Self.ohmmeterTestCurrent
    }

    /// Effective resistance of a simple two-terminal resistive part.
    func resistance(of comp: CircuitComponent) -> Double? {
        switch comp.kind {
        case .resistor:
            return max(comp.value, 1e-6)

        case .switchSPST:
            return comp.stateBool ? Self.closedContactResistance : Self.openCircuitResistance

        case .rheostat:
            return max(comp.value * Self.wiperRatio(of: comp), 1e-6)

        case .lamp:
            // Cold filament resistance; brightness is driven off the solved current.
            return max(comp.value > 0 ? comp.value : 10.0, 1e-3)

        case .fuse:
            return comp.stateBool ? max(comp.value > 0 ? comp.value : 0.05, 1e-4) : Self.openCircuitResistance

        case .thermistor:
            // NTC: R(T) = R25 * exp(B * (1/T - 1/298.15))
            let r25 = max(comp.value > 0 ? comp.value : 10_000.0, 1e-3)
            let kelvin = max((comp.secondaryValue > -270 ? comp.secondaryValue : 25.0) + 273.15, 1.0)
            return r25 * exp(Self.thermistorBeta * (1.0 / kelvin - 1.0 / Self.thermistorReferenceKelvin))

        case .photoResistor:
            // CdS cell: roughly R = R(10 lux) * (lux / 10) ^ -0.7
            let base = max(comp.value > 0 ? comp.value : 5_000.0, 1e-3)
            let lux = max(comp.secondaryValue > 0 ? comp.secondaryValue : 10.0, 0.1)
            return base * pow(lux / 10.0, -0.7)

        case .ammeter:
            return comp.value > 0 ? max(comp.value, 1e-6) : Self.idealAmmeterResistance

        case .voltmeter:
            return comp.value > 0 ? comp.value : Self.idealVoltmeterResistance

        case .galvanometer:
            return comp.value > 0 ? comp.value : 100.0

        case .multimeter:
            return multimeterResistance(comp)

        default:
            return nil
        }
    }

    // MARK: - Matrix stamping primitives

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

    // MARK: - Logic

    /// High = 5.0V, Low = 0.0V. Threshold = 2.5V.
    private func evaluateLogicGate(comp: CircuitComponent, nodes n: [Int], voltages: [Int: Double]) -> Double {
        let in1 = voltage(of: n.first ?? 0, in: voltages) > 2.5
        let in2 = n.count > 1 ? voltage(of: n[1], in: voltages) > 2.5 : false

        let result: Bool
        switch comp.kind {
        case .logicAND: result = in1 && in2
        case .logicOR: result = in1 || in2
        case .logicNAND: result = !(in1 && in2)
        case .logicNOR: result = !(in1 || in2)
        case .logicXOR: result = in1 != in2
        case .logicXNOR: result = in1 == in2
        case .logicNOT: result = !in1
        case .logicBuffer: result = in1
        default: result = false
        }
        return result ? 5.0 : 0.0
    }

    // MARK: - Runtime state

    private func updateComponentRuntimeStates(voltages: [Int: Double], dt: Double) {
        for comp in circuit.components {
            let n = nodeIndices(for: comp)
            func v(_ i: Int) -> Double { i < n.count ? voltage(of: n[i], in: voltages) : 0.0 }

            let vDrop = v(0) - v(1)
            comp.runtimeVoltageDrop = vDrop

            switch comp.kind {
            case .resistor, .switchSPST, .rheostat, .lamp, .fuse, .thermistor, .photoResistor,
                 .ammeter, .voltmeter, .galvanometer:
                let r = resistance(of: comp) ?? 1.0
                comp.runtimeCurrent = vDrop / r

            case .multimeter:
                if MeterMode(rawValue: comp.modeIndex) == .resistance {
                    comp.runtimeCurrent = ohmmeterTestCurrent(for: comp)
                } else {
                    comp.runtimeCurrent = vDrop / multimeterResistance(comp)
                }

            case .potentiometer:
                // Report the A-W segment, which is what the wiper delivers to the circuit.
                let rAW = max(comp.value * Self.wiperRatio(of: comp), 1e-6)
                if n.count >= 3 {
                    comp.runtimeVoltageDrop = v(0) - v(2)
                    comp.runtimeCurrent = (v(0) - v(2)) / rAW
                } else {
                    comp.runtimeCurrent = vDrop / rAW
                }

            case .wattmeter:
                let ccR = max(comp.value > 0 ? comp.value : 0.05, 1e-4)
                let iCC = (v(0) - v(1)) / ccR
                let vPC = v(2) - v(3)
                comp.runtimeCurrent = iCC
                comp.runtimeVoltageDrop = vPC
                comp.runtimeReading = abs(iCC * vPC)

            case .capacitor, .electrolyticCapacitor, .trimmerCapacitor:
                let c = max(comp.value, 1e-15)
                comp.runtimeCurrent = c * (vDrop - comp.runtimePrevVoltage) / dt
                comp.runtimePrevVoltage = vDrop

            case .inductor:
                let l = max(comp.value, 1e-12)
                let newI = comp.runtimePrevCurrent + (vDrop * dt / l)
                comp.runtimeCurrent = newI
                comp.runtimePrevCurrent = newI

            case .diode, .led, .schottkyDiode:
                let model = Self.junctionModel(for: comp)
                let vt = Self.Vt * model.emissionCoefficient
                let clampedVd = min(max(vDrop, -10.0), 1.5)
                comp.runtimeCurrent = model.saturation * (exp(clampedVd / vt) - 1.0)
                comp.runtimePrevVoltage = vDrop

            case .zenerDiode:
                let vz = comp.secondaryValue > 0 ? comp.secondaryValue : 5.1
                if vDrop < -vz {
                    comp.runtimeCurrent = -(-vDrop - vz) / 10.0
                } else {
                    comp.runtimeCurrent = vDrop > 0.6 ? vDrop / 0.1 : 0.0
                }
                comp.runtimePrevVoltage = vDrop

            case .ohmmeter:
                let test = ohmmeterTestCurrent(for: comp)
                comp.runtimeCurrent = test
                comp.runtimeReading = abs(vDrop) / test

            case .probe:
                comp.runtimeCurrent = 0.0
                comp.runtimeReading = v(0)

            default:
                break
            }

            updateInstrumentReading(comp)
        }

        blowFuses()

        // Update runtime current on wires for visual animation
        for i in 0..<circuit.wires.count {
            let wire = circuit.wires[i]
            if let comp = circuit.components.first(where: { c in c.pins.contains { $0.id == wire.startPinId } }) {
                circuit.wires[i].runtimeCurrent = comp.runtimeCurrent
            }
        }
    }

    /// Instruments publish their measured quantity in `runtimeReading` so the faceplate can show it.
    private func updateInstrumentReading(_ comp: CircuitComponent) {
        switch comp.kind {
        case .ammeter, .galvanometer:
            comp.runtimeReading = abs(comp.runtimeCurrent)
        case .multimeter:
            switch MeterMode(rawValue: comp.modeIndex) ?? .voltage {
            case .voltage:
                comp.runtimeReading = abs(comp.runtimeVoltageDrop)
            case .current:
                comp.runtimeReading = abs(comp.runtimeCurrent)
            case .resistance:
                comp.runtimeReading = comp.runtimeCurrent > 1e-12 ? abs(comp.runtimeVoltageDrop) / comp.runtimeCurrent : 0
            }
        case .voltmeter:
            comp.runtimeReading = abs(comp.runtimeVoltageDrop)
        case .probe:
            break
        default:
            break
        }
    }

    /// A fuse that carries more than its rating opens permanently, exactly like the real part.
    private func blowFuses() {
        for comp in circuit.components where comp.kind == .fuse && comp.stateBool {
            let rating = comp.secondaryValue > 0 ? comp.secondaryValue : 1.0
            if abs(comp.runtimeCurrent) > rating {
                comp.stateBool = false
            }
        }
    }

    /// Resets a blown fuse so the experiment can be repeated.
    public func resetFuses() {
        for comp in circuit.components where comp.kind == .fuse {
            comp.stateBool = true
        }
    }

    // MARK: - Public lookups used by the UI

    /// Node voltage at a pin, for probe badges and instrument faces.
    public func nodeVoltage(atPin pinId: UUID, in voltages: [Int: Double]) -> Double {
        voltage(of: pinToNode[pinId] ?? 0, in: voltages)
    }

    /// Galvanometer needle position, 0...1 of full-scale deflection.
    public static func galvanometerDeflection(of comp: CircuitComponent) -> Double {
        let fullScale = comp.secondaryValue > 0 ? comp.secondaryValue : 1e-3
        guard fullScale > 0 else { return 0 }
        return min(max(abs(comp.runtimeCurrent) / fullScale, 0), 1)
    }
}
