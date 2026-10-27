import SwiftUI
import Combine
import MultiSimEngine

/// The central state manager for schematic editing, simulation ticking, and virtual instruments.
@MainActor
public final class CircuitEditorViewModel: ObservableObject {
    // MARK: - Document State
    @Published public var circuit: Circuit
    @Published public var selectedComponentId: UUID? = nil
    @Published public var selectedWireId: UUID? = nil

    // MARK: - Canvas State
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var panOffset: CGPoint = .zero
    @Published public var gridSize: CGFloat = 20.0
    @Published public var wireDraftStartPin: (componentId: UUID, pin: Pin)? = nil
    @Published public var wireDraftCurrentPoint: CGPoint? = nil
    @Published public var isWireMode: Bool = false
    @Published public var showNodeVoltages: Bool = true
    @Published public var showDiagnosticsSheet: Bool = false
    @Published public var lastConnectedWireDescription: String? = nil
    @Published public var latestNodeVoltages: [Int: Double] = [:]

    // MARK: - Simulation State
    @Published public var isSimulating: Bool = true
    @Published public var simulationSpeed: Double = 1.0 // 1x real time
    @Published public var currentSimulationTime: Double = 0.0
    @Published public var animationPhase: Double = 0.0 // Phase for moving current dots

    // MARK: - Virtual Instruments
    @Published public var showOscilloscope: Bool = true
    @Published public var oscilloscopeChannelACompId: UUID? = nil
    @Published public var oscilloscopeChannelBCompId: UUID? = nil
    @Published public var oscilloscopeTimeScale: Double = 0.005 // 5ms per div
    @Published public var oscilloscopeVoltsPerDivA: Double = 2.0
    @Published public var oscilloscopeVoltsPerDivB: Double = 2.0

    // Waveform history buffers for oscilloscope (ring buffers)
    public var traceA: [(time: Double, voltage: Double)] = []
    public var traceB: [(time: Double, voltage: Double)] = []
    private let maxTraceSamples = 800

    // Solver instance
    public private(set) var solver: MNASolver
    private var simulationTimer: AnyCancellable?

    public init(circuit: Circuit? = nil) {
        let initialCircuit = circuit ?? Self.createStarterCircuit()
        self.circuit = initialCircuit
        self.solver = MNASolver(circuit: initialCircuit, timeStep: 1e-4)

        // Default probe channel A to first passive/diode component
        if let firstComp = initialCircuit.components.first(where: { $0.kind == .capacitor || $0.kind == .diode || $0.kind == .resistor }) {
            self.oscilloscopeChannelACompId = firstComp.id
        }

        startSimulationTimer()
    }

    // MARK: - Simulation Control

    public func toggleSimulation() {
        isSimulating.toggle()
    }

    public func resetSimulation() {
        solver.reset()
        currentSimulationTime = 0.0
        traceA.removeAll(keepingCapacity: true)
        traceB.removeAll(keepingCapacity: true)
        animationPhase = 0.0
    }

    public func stepSimulationSingle() {
        advanceSimulation(dt: solver.timeStep)
    }

    private func startSimulationTimer() {
        // Run timer at ~60 FPS (approx every 16.6 ms)
        simulationTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isSimulating else { return }
                // In 16.6ms at 1x speed, do 16 steps of 100 microseconds (1.6ms simulated time) or scaled
                let stepsPerFrame = max(1, Int(16 * self.simulationSpeed))
                let dt = self.solver.timeStep
                for _ in 0..<stepsPerFrame {
                    self.advanceSimulation(dt: dt)
                }
                // Animate electron dots
                self.animationPhase += 1.5 * self.simulationSpeed
                if self.animationPhase > 1000.0 {
                    self.animationPhase = 0.0
                }
            }
    }

    private func advanceSimulation(dt: Double) {
        let res = solver.step(dt: dt)
        currentSimulationTime = res.time
        latestNodeVoltages = res.nodeVoltages

        // Record oscilloscope samples
        if let compAId = oscilloscopeChannelACompId,
           let compA = circuit.components.first(where: { $0.id == compAId }) {
            traceA.append((time: currentSimulationTime, voltage: compA.runtimeVoltageDrop))
            if traceA.count > maxTraceSamples { traceA.removeFirst() }
        }

        if let compBId = oscilloscopeChannelBCompId,
           let compB = circuit.components.first(where: { $0.id == compBId }) {
            traceB.append((time: currentSimulationTime, voltage: compB.runtimeVoltageDrop))
            if traceB.count > maxTraceSamples { traceB.removeFirst() }
        }
    }

    // MARK: - Circuit Modification

    public func addComponent(kind: ComponentKind, at position: CGPoint) {
        let count = circuit.components.filter { $0.kind == kind }.count + 1
        let prefix: String
        var defVal: Double = 0.0
        var defSec: Double = 0.0

        switch kind {
        case .resistor: prefix = "R"; defVal = 1000.0
        case .capacitor: prefix = "C"; defVal = 1e-6
        case .inductor: prefix = "L"; defVal = 1e-3
        case .dcVoltageSource: prefix = "V"; defVal = 5.0
        case .acVoltageSource: prefix = "V"; defVal = 5.0; defSec = 60.0 // 5V peak, 60Hz
        case .clockSource: prefix = "CLK"; defVal = 5.0; defSec = 1000.0 // 5V, 1kHz
        case .dcCurrentSource: prefix = "I"; defVal = 0.01 // 10mA
        case .ground: prefix = "GND"
        case .switchSPST: prefix = "SW"
        case .potentiometer: prefix = "POT"; defVal = 10000.0; defSec = 0.5
        case .diode: prefix = "D"
        case .led: prefix = "LED"; defVal = 2.0
        case .zenerDiode: prefix = "ZD"; defSec = 5.1
        case .bjtNPN: prefix = "Q"; defSec = 100.0
        case .bjtPNP: prefix = "Q"; defSec = 100.0
        case .opAmp: prefix = "U"
        case .vcvs: prefix = "E"; defVal = 2.0 // Gain mu = 2.0
        case .vccs: prefix = "G"; defVal = 0.05 // gm = 50 mS
        case .logicAND: prefix = "U_AND"
        case .logicOR: prefix = "U_OR"
        case .logicNOT: prefix = "U_NOT"
        case .logicNAND: prefix = "U_NAND"
        case .logicNOR: prefix = "U_NOR"
        case .logicXOR: prefix = "U_XOR"
        }

        let snappedX = round(position.x / gridSize) * gridSize
        let snappedY = round(position.y / gridSize) * gridSize

        let comp = CircuitComponent(
            kind: kind,
            designator: "\(prefix)\(count)",
            position: Point2D(x: snappedX, y: snappedY),
            value: defVal,
            secondaryValue: defSec
        )

        circuit.components.append(comp)
        selectedComponentId = comp.id
        solver.rebuildNetlist()
    }

    public func rotateSelected() {
        guard let id = selectedComponentId,
              let comp = circuit.components.first(where: { $0.id == id }) else { return }
        comp.rotation = (comp.rotation + 90) % 360
        solver.rebuildNetlist()
        objectWillChange.send()
    }

    public func updateComponentPosition(id: UUID, newPosition: Point2D) {
        if let comp = circuit.components.first(where: { $0.id == id }) {
            comp.position = newPosition
            objectWillChange.send()
        }
    }

    public func deleteSelected() {
        if let id = selectedComponentId {
            // Remove connected wires
            let pinIds = Set(circuit.components.first(where: { $0.id == id })?.pins.map { $0.id } ?? [])
            circuit.wires.removeAll { pinIds.contains($0.startPinId) || pinIds.contains($0.endPinId) }
            circuit.components.removeAll { $0.id == id }
            selectedComponentId = nil
            solver.rebuildNetlist()
        } else if let wireId = selectedWireId {
            circuit.wires.removeAll { $0.id == wireId }
            selectedWireId = nil
            solver.rebuildNetlist()
        }
    }

    public func toggleSwitch(componentId: UUID) {
        guard let comp = circuit.components.first(where: { $0.id == componentId }),
              comp.kind == .switchSPST else { return }
        comp.stateBool.toggle()
    }

    // MARK: - Wiring Logic

    public func handlePinClicked(componentId: UUID, pin: Pin) {
        if let draft = wireDraftStartPin {
            // If clicked different pin, complete the wire!
            if draft.pin.id != pin.id {
                let wire = Wire(startPinId: draft.pin.id, endPinId: pin.id)
                circuit.wires.append(wire)
                solver.rebuildNetlist()

                let startName = circuit.components.first(where: { $0.id == draft.componentId })?.designator ?? "Pin"
                let targetName = circuit.components.first(where: { $0.id == componentId })?.designator ?? "Pin"
                lastConnectedWireDescription = "✅ Connected \(startName) to \(targetName)"
            }
            wireDraftStartPin = nil
            wireDraftCurrentPoint = nil
        } else {
            // Start wiring from this pin
            wireDraftStartPin = (componentId, pin)
            if let startComp = circuit.components.first(where: { $0.id == componentId }) {
                let p = startComp.absolutePinPosition(pinIndex: pin.index)
                wireDraftCurrentPoint = CGPoint(x: p.x, y: p.y)
                lastConnectedWireDescription = "⚡️ Wiring from \(startComp.designator) pin '\(pin.name)'... Click target pin to connect"
            }
        }
    }

    public func cancelWiring() {
        wireDraftStartPin = nil
        wireDraftCurrentPoint = nil
        lastConnectedWireDescription = nil
    }

    public func diagnoseCircuit() -> CircuitDiagnosticReport {
        return CircuitDiagnostics.diagnose(circuit: circuit, solver: solver)
    }

    // MARK: - Starter Preset Circuits

    public static func createStarterCircuit() -> Circuit {
        // Preset: AC Source -> Diode -> RC Filter (Half-wave rectifier with filter capacitor)
        let vsrc = CircuitComponent(kind: .acVoltageSource, designator: "V1", position: Point2D(x: 140, y: 240), rotation: 0, value: 9.0, secondaryValue: 50.0)
        let d1 = CircuitComponent(kind: .diode, designator: "D1", position: Point2D(x: 280, y: 160), rotation: 0)
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 420, y: 240), rotation: 90, value: 1000.0)
        let c1 = CircuitComponent(kind: .capacitor, designator: "C1", position: Point2D(x: 360, y: 240), rotation: 90, value: 47e-6)
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 280, y: 340), rotation: 0)

        // Connect components
        let w1 = Wire(startPinId: vsrc.pins[0].id, endPinId: d1.pins[0].id)
        let w2 = Wire(startPinId: d1.pins[1].id, endPinId: c1.pins[0].id)
        let w3 = Wire(startPinId: c1.pins[0].id, endPinId: r1.pins[0].id)
        let w4 = Wire(startPinId: r1.pins[1].id, endPinId: c1.pins[1].id)
        let w5 = Wire(startPinId: c1.pins[1].id, endPinId: gnd.pins[0].id)
        let w6 = Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id)

        return Circuit(components: [vsrc, d1, r1, c1, gnd], wires: [w1, w2, w3, w4, w5, w6])
    }

    public func loadPreset(type: PresetType) {
        switch type {
        case .kvlKclVerification:
            // Lab 1: KVL & KCL Loop & Nodal Verification
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 160, y: 240), value: 12.0)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 280, y: 160), value: 4.0)
            let r2 = CircuitComponent(kind: .resistor, designator: "R2", position: Point2D(x: 400, y: 240), rotation: 90, value: 6.0)
            let r3 = CircuitComponent(kind: .resistor, designator: "R3", position: Point2D(x: 480, y: 240), rotation: 90, value: 12.0)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 320, y: 340))

            let w1 = Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id)
            let w2 = Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id)
            let w3 = Wire(startPinId: r1.pins[1].id, endPinId: r3.pins[0].id)
            let w4 = Wire(startPinId: r2.pins[1].id, endPinId: gnd.pins[0].id)
            let w5 = Wire(startPinId: r3.pins[1].id, endPinId: gnd.pins[0].id)
            let w6 = Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id)
            self.circuit = Circuit(components: [v1, r1, r2, r3, gnd], wires: [w1, w2, w3, w4, w5, w6])

        case .theveninTheorem:
            // Lab 2: Thevenin's & Norton's Theorem
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 160, y: 240), value: 20.0)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 280, y: 160), value: 10.0)
            let r2 = CircuitComponent(kind: .resistor, designator: "R2", position: Point2D(x: 380, y: 240), rotation: 90, value: 40.0)
            let rl = CircuitComponent(kind: .resistor, designator: "R_LOAD", position: Point2D(x: 480, y: 240), rotation: 90, value: 8.0)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 320, y: 340))

            let w1 = Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id)
            let w2 = Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id)
            let w3 = Wire(startPinId: r1.pins[1].id, endPinId: rl.pins[0].id)
            let w4 = Wire(startPinId: r2.pins[1].id, endPinId: gnd.pins[0].id)
            let w5 = Wire(startPinId: rl.pins[1].id, endPinId: gnd.pins[0].id)
            let w6 = Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id)
            self.circuit = Circuit(components: [v1, r1, r2, rl, gnd], wires: [w1, w2, w3, w4, w5, w6])

        case .maxPowerTransfer:
            // Lab 3: Maximum Power Transfer (RL Sweep)
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 160, y: 240), value: 12.0)
            let rs = CircuitComponent(kind: .resistor, designator: "R_SOURCE", position: Point2D(x: 280, y: 160), value: 100.0)
            let rl = CircuitComponent(kind: .potentiometer, designator: "R_LOAD", position: Point2D(x: 400, y: 240), rotation: 90, value: 500.0, secondaryValue: 0.2)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 280, y: 340))

            let w1 = Wire(startPinId: v1.pins[0].id, endPinId: rs.pins[0].id)
            let w2 = Wire(startPinId: rs.pins[1].id, endPinId: rl.pins[0].id)
            let w3 = Wire(startPinId: rl.pins[1].id, endPinId: gnd.pins[0].id)
            let w4 = Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id)
            self.circuit = Circuit(components: [v1, rs, rl, gnd], wires: [w1, w2, w3, w4])

        case .rlcResonance:
            // Lab 4: Series RLC Resonance (f0 = 1591 Hz)
            let v1 = CircuitComponent(kind: .acVoltageSource, designator: "V1", position: Point2D(x: 140, y: 240), value: 10.0, secondaryValue: 1591.0)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 260, y: 160), value: 10.0)
            let l1 = CircuitComponent(kind: .inductor, designator: "L1", position: Point2D(x: 360, y: 160), value: 10e-3)
            let c1 = CircuitComponent(kind: .capacitor, designator: "C1", position: Point2D(x: 460, y: 240), rotation: 90, value: 1e-6)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 300, y: 340))

            let w1 = Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id)
            let w2 = Wire(startPinId: r1.pins[1].id, endPinId: l1.pins[0].id)
            let w3 = Wire(startPinId: l1.pins[1].id, endPinId: c1.pins[0].id)
            let w4 = Wire(startPinId: c1.pins[1].id, endPinId: gnd.pins[0].id)
            let w5 = Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id)
            self.circuit = Circuit(components: [v1, r1, l1, c1, gnd], wires: [w1, w2, w3, w4, w5])

        case .fullWaveBridge:
            // Lab 5: Full-Wave Bridge Rectifier with Filter
            let v1 = CircuitComponent(kind: .acVoltageSource, designator: "V1", position: Point2D(x: 120, y: 240), value: 12.0, secondaryValue: 50.0)
            let d1 = CircuitComponent(kind: .diode, designator: "D1", position: Point2D(x: 260, y: 180), rotation: 0)
            let d2 = CircuitComponent(kind: .diode, designator: "D2", position: Point2D(x: 360, y: 180), rotation: 0)
            let d3 = CircuitComponent(kind: .diode, designator: "D3", position: Point2D(x: 260, y: 280), rotation: 0)
            let d4 = CircuitComponent(kind: .diode, designator: "D4", position: Point2D(x: 360, y: 280), rotation: 0)
            let c1 = CircuitComponent(kind: .capacitor, designator: "C_FILTER", position: Point2D(x: 460, y: 240), rotation: 90, value: 47e-6)
            let rLoad = CircuitComponent(kind: .resistor, designator: "R_LOAD", position: Point2D(x: 540, y: 240), rotation: 90, value: 1000.0)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 360, y: 360))

            // AC connects to Bridge AC inputs
            let w1 = Wire(startPinId: v1.pins[0].id, endPinId: d1.pins[0].id)
            let w2 = Wire(startPinId: d1.pins[0].id, endPinId: d3.pins[1].id)
            let w3 = Wire(startPinId: v1.pins[1].id, endPinId: d2.pins[0].id)
            let w4 = Wire(startPinId: d2.pins[0].id, endPinId: d4.pins[1].id)

            // DC Positive Output
            let w5 = Wire(startPinId: d1.pins[1].id, endPinId: d2.pins[1].id)
            let w6 = Wire(startPinId: d2.pins[1].id, endPinId: c1.pins[0].id)
            let w7 = Wire(startPinId: c1.pins[0].id, endPinId: rLoad.pins[0].id)

            // DC Negative Output to Ground
            let w8 = Wire(startPinId: d3.pins[0].id, endPinId: d4.pins[0].id)
            let w9 = Wire(startPinId: d4.pins[0].id, endPinId: c1.pins[1].id)
            let w10 = Wire(startPinId: c1.pins[1].id, endPinId: rLoad.pins[1].id)
            let w11 = Wire(startPinId: c1.pins[1].id, endPinId: gnd.pins[0].id)

            self.circuit = Circuit(
                components: [v1, d1, d2, d3, d4, c1, rLoad, gnd],
                wires: [w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11]
            )

        case .halfWaveRectifier:
            self.circuit = Self.createStarterCircuit()

        case .rcLowPassFilter:
            let vsrc = CircuitComponent(kind: .acVoltageSource, designator: "V1", position: Point2D(x: 160, y: 240), value: 5.0, secondaryValue: 1000.0)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 280, y: 180), value: 1000.0)
            let c1 = CircuitComponent(kind: .capacitor, designator: "C1", position: Point2D(x: 380, y: 240), rotation: 90, value: 1e-7)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 280, y: 340))
            let w1 = Wire(startPinId: vsrc.pins[0].id, endPinId: r1.pins[0].id)
            let w2 = Wire(startPinId: r1.pins[1].id, endPinId: c1.pins[0].id)
            let w3 = Wire(startPinId: c1.pins[1].id, endPinId: gnd.pins[0].id)
            let w4 = Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id)
            self.circuit = Circuit(components: [vsrc, r1, c1, gnd], wires: [w1, w2, w3, w4])

        case .ledSwitchCircuit:
            let vsrc = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 160, y: 240), value: 9.0)
            let sw = CircuitComponent(kind: .switchSPST, designator: "SW1", position: Point2D(x: 260, y: 160), stateBool: true)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 360, y: 160), value: 330.0)
            let led = CircuitComponent(kind: .led, designator: "LED1", position: Point2D(x: 440, y: 240), rotation: 90, ledColor: .green)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 300, y: 340))
            let w1 = Wire(startPinId: vsrc.pins[0].id, endPinId: sw.pins[0].id)
            let w2 = Wire(startPinId: sw.pins[1].id, endPinId: r1.pins[0].id)
            let w3 = Wire(startPinId: r1.pins[1].id, endPinId: led.pins[0].id)
            let w4 = Wire(startPinId: led.pins[1].id, endPinId: gnd.pins[0].id)
            let w5 = Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id)
            self.circuit = Circuit(components: [vsrc, sw, r1, led, gnd], wires: [w1, w2, w3, w4, w5])
        }

        self.solver = MNASolver(circuit: self.circuit, timeStep: 1e-4)
        self.selectedComponentId = nil
        self.selectedWireId = nil
        resetSimulation()
    }
}

public enum PresetType: String, CaseIterable, Identifiable {
    case kvlKclVerification = "Lab 1: KVL & KCL Verification"
    case theveninTheorem = "Lab 2: Thevenin's & Norton's Theorem"
    case maxPowerTransfer = "Lab 3: Maximum Power Transfer"
    case rlcResonance = "Lab 4: Series RLC Resonance (1.59 kHz)"
    case fullWaveBridge = "Lab 5: Full-Wave Bridge Rectifier"
    case halfWaveRectifier = "Example: Half-Wave Rectifier"
    case rcLowPassFilter = "Example: RC Low-Pass Filter"
    case ledSwitchCircuit = "Example: Interactive LED & Switch"

    public var id: String { rawValue }
}
