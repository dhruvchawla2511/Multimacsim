import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import MultiSimEngine

/// The central state manager for schematic editing, simulation ticking, and virtual instruments.
@MainActor
public final class CircuitEditorViewModel: ObservableObject {
    // MARK: - Document State
    @Published public var circuit: Circuit
    @Published public var selectedComponentId: UUID? = nil
    @Published public var selectedWireId: UUID? = nil
    @Published public var currentFileURL: URL? = nil
    private var moveOrigins: [UUID: Point2D] = [:]

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
    /// The terminal the current wire draft will land on if you let go now.
    @Published public var wireDraftTargetPinId: UUID? = nil

    // MARK: - Simulation State
    @Published public var isSimulating: Bool = true
    @Published public var simulationSpeed: Double = 1.0 // 1x real time
    @Published public var currentSimulationTime: Double = 0.0
    @Published public var animationPhase: Double = 0.0 // Phase for moving current dots

    // MARK: - Virtual Instruments
    @Published public var showOscilloscope: Bool = false
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
        let initialCircuit = circuit ?? Circuit()
        self.circuit = initialCircuit
        self.solver = MNASolver(circuit: initialCircuit, timeStep: 1e-4)

        // Default probe channel A to first passive/diode component
        if let firstComp = initialCircuit.components.first(where: { $0.kind.isCapacitive || $0.kind.isJunctionDiode || $0.kind == .resistor }) {
            self.oscilloscopeChannelACompId = firstComp.id
        }

        startSimulationTimer()
    }

    /// Opens with a pre-wired example so the canvas is never an empty mystery.
    public convenience init(preset: PresetType) {
        self.init(circuit: Circuit())
        loadPreset(type: preset)
    }

    // MARK: - Simulation Control

    public func toggleSimulation() {
        isSimulating.toggle()
    }

    public func resetSimulation() {
        solver.reset()
        solver.resetFuses()
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

    public func addComponent(kind: ComponentKind, at position: Point2D) {
        let count = circuit.components.filter { $0.kind == kind }.count + 1
        let defaults = kind.partDefaults

        let snappedX = WireRouter.snap(position.x, to: gridSize)
        let snappedY = WireRouter.snap(position.y, to: gridSize)

        let comp = CircuitComponent(
            kind: kind,
            designator: "\(kind.designatorPrefix)\(count)",
            position: Point2D(x: snappedX, y: snappedY),
            value: defaults.value,
            secondaryValue: defaults.secondaryValue,
            stateBool: defaults.isClosed,
            modeIndex: defaults.modeIndex
        )

        circuit.components.append(comp)
        selectedComponentId = comp.id

        // Drop it straight onto a terminal or alongside a facing terminal and it wires itself.
        let wired = connectComponent(comp)
        solver.rebuildNetlist()
        if wired > 0 {
            lastConnectedWireDescription = "🔗 \(comp.designator) auto-connected (\(wired))"
        }
    }

    /// First empty spot in the visible area, so parts added from the palette never pile up.
    public func nextFreePosition() -> Point2D {
        let baseX = 200.0 - Double(panOffset.x)
        let baseY = 160.0 - Double(panOffset.y)
        for row in 0..<6 {
            for col in 0..<6 {
                let cx = baseX + Double(col) * 120.0
                let cy = baseY + Double(row) * 100.0
                let taken = circuit.components.contains { c in
                    abs(c.position.x - cx) < 80.0 && abs(c.position.y - cy) < 70.0
                }
                if !taken {
                    return Point2D(x: cx, y: cy)
                }
            }
        }
        return Point2D(x: baseX, y: baseY)
    }

    // MARK: - Moving parts

    public func beginMoving(id: UUID) {
        if let comp = circuit.components.first(where: { $0.id == id }) {
            moveOrigins[id] = comp.position
        }
    }

    public func dragOrigin(for id: UUID) -> Point2D? {
        moveOrigins[id]
    }

    /// Dragging is magnetic: the part is nudged so a terminal grabs the nearest terminal or wire.
    public func updateComponentPosition(id: UUID, newPosition: Point2D) {
        guard let comp = circuit.components.first(where: { $0.id == id }) else { return }
        let grid = Point2D(
            x: WireRouter.snap(newPosition.x, to: gridSize),
            y: WireRouter.snap(newPosition.y, to: gridSize)
        )
        comp.position = AutoConnect.snappedPosition(moving: comp, proposed: grid, in: circuit, grid: Double(gridSize)) ?? grid
        objectWillChange.send()
    }

    public func finishMovingComponent(id: UUID) {
        moveOrigins[id] = nil
        if let comp = circuit.components.first(where: { $0.id == id }) {
            let wired = connectComponent(comp)
            if wired > 0 {
                lastConnectedWireDescription = "✅ \(comp.designator) connected (\(wired) wire\(wired == 1 ? "" : "s"))"
            }
        }
        solver.rebuildNetlist()
        objectWillChange.send()
    }

    private func hasWire(between a: UUID, and b: UUID) -> Bool {
        circuit.wires.contains { w in
            (w.startPinId == a && w.endPinId == b) || (w.startPinId == b && w.endPinId == a)
        }
    }

    /// Wires every terminal of a component that is now touching another terminal, or touching a wire.
    @discardableResult
    private func connectComponent(_ comp: CircuitComponent) -> Int {
        var added = 0

        // Terminal sitting on terminal.
        for pair in AutoConnect.coincidentPairs(in: circuit) {
            guard pair.a == comp.id || pair.b == comp.id || belongsTo(comp, pair.a) || belongsTo(comp, pair.b) else { continue }
            if !hasWire(between: pair.a, and: pair.b) {
                circuit.wires.append(Wire(startPinId: pair.a, endPinId: pair.b))
                added += 1
            }
        }

        // Terminal dropped onto an existing wire becomes a T-junction on that net.
        for pin in comp.pins {
            let p = comp.absolutePinPosition(pinIndex: pin.index)
            guard let tap = AutoConnect.nearestTapPoint(from: p, in: circuit, grid: Double(gridSize), tolerance: 1.5) else { continue }
            let tapEnd = tapEndPin(for: tap.wire, near: p)
            if !hasWire(between: pin.id, and: tapEnd) {
                circuit.wires.append(Wire(startPinId: pin.id, endPinId: tapEnd, waypoints: [tap.point]))
                added += 1
            }
        }

        return added
    }

    private func belongsTo(_ comp: CircuitComponent, _ pinId: UUID) -> Bool {
        comp.pins.contains { $0.id == pinId }
    }

    /// The endpoint of a wire nearest to a tapped point - joining it puts the pin on that net.
    private func tapEndPin(for wire: Wire, near point: Point2D) -> UUID {
        guard let a = circuit.pinPosition(wire.startPinId), let b = circuit.pinPosition(wire.endPinId) else {
            return wire.startPinId
        }
        return point.distance(to: a) <= point.distance(to: b) ? wire.startPinId : wire.endPinId
    }

    // MARK: - Wiring actions

    /// Connects terminals that already face each other down the same row or column.
    @discardableResult
    public func autoConnectFacingPins() -> Int {
        let pairs = AutoConnect.facingPairs(in: circuit, maxGap: 60 * 2, grid: Double(gridSize))
        var added = 0
        for pair in pairs {
            if !hasWire(between: pair.from.id, and: pair.to.id) {
                circuit.wires.append(Wire(startPinId: pair.from.id, endPinId: pair.to.id))
                added += 1
            }
        }
        solver.rebuildNetlist()
        lastConnectedWireDescription = added == 0
            ? "ℹ️ No facing terminals found within reach - nudge the parts closer or drag from dot to dot"
            : "🔗 Auto-connect added \(added) wire\(added == 1 ? "" : "s")"
        objectWillChange.send()
        return added
    }

    /// Rounds every part back onto the grid, then re-checks for touch connections.
    public func snapAllToGrid() {
        for comp in circuit.components {
            comp.position = Point2D(
                x: WireRouter.snap(comp.position.x, to: gridSize),
                y: WireRouter.snap(comp.position.y, to: gridSize)
            )
        }
        let before = circuit.wires.count
        for comp in circuit.components {
            _ = connectComponent(comp)
        }
        solver.rebuildNetlist()
        let created = circuit.wires.count - before
        lastConnectedWireDescription = created == 0
            ? "📐 Aligned to grid"
            : "📐 Aligned to grid - \(created) new connection\(created == 1 ? "" : "s")"
        objectWillChange.send()
    }

    // MARK: - File: New / Open / Save

    public var documentName: String {
        currentFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    private func loadCircuit(_ newCircuit: Circuit, url: URL?) {
        circuit = newCircuit
        solver = MNASolver(circuit: newCircuit, timeStep: 1e-4)
        currentFileURL = url
        selectedComponentId = nil
        selectedWireId = nil
        cancelWiring()
        panOffset = .zero
        oscilloscopeChannelACompId = newCircuit.components.first(where: { $0.kind.isCapacitive || $0.kind.isJunctionDiode || $0.kind == .resistor })?.id
        oscilloscopeChannelBCompId = nil
        resetSimulation()
    }

    public func newDocument() {
        if !circuit.components.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Start a new circuit?"
            alert.informativeText = "The current circuit will be closed. Anything you have not saved will be lost."
            alert.addButton(withTitle: "Discard & New")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        loadCircuit(Circuit(), url: nil)
        lastConnectedWireDescription = nil
    }

    public func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Open a MultiSim circuit"
        if let t = UTType(filenameExtension: "msim") {
            panel.allowedContentTypes = [t, UTType.json]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode(Circuit.self, from: data)
            loadCircuit(loaded, url: url)
            lastConnectedWireDescription = "📂 Opened \(url.lastPathComponent)"
        } catch {
            showFileError("Could not open the file.", error)
        }
    }

    public func saveDocument() {
        if let url = currentFileURL {
            write(to: url)
        } else {
            saveDocumentAs()
        }
    }

    public func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(documentName).msim"
        panel.message = "Save your circuit"
        if let t = UTType(filenameExtension: "msim") {
            panel.allowedContentTypes = [t]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(circuit)
            try data.write(to: url, options: .atomic)
            currentFileURL = url
            lastConnectedWireDescription = "💾 Saved \(url.lastPathComponent)"
        } catch {
            showFileError("Could not save the file.", error)
        }
    }

    private func showFileError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    public func rotateSelected() {
        guard let id = selectedComponentId,
              let comp = circuit.components.first(where: { $0.id == id }) else { return }
        comp.rotation = (comp.rotation + 90) % 360
        _ = connectComponent(comp)
        solver.rebuildNetlist()
        objectWillChange.send()
    }

    public func deleteSelected() {
        if let id = selectedComponentId {
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
        objectWillChange.send()
    }

    // MARK: - Wiring Logic

    public func handlePinClicked(componentId: UUID, pin: Pin) {
        if let draft = wireDraftStartPin {
            // If clicked different pin, complete the wire!
            if draft.pin.id != pin.id {
                if !hasWire(between: draft.pin.id, and: pin.id) {
                    circuit.wires.append(Wire(startPinId: draft.pin.id, endPinId: pin.id))
                }
                solver.rebuildNetlist()

                let startName = circuit.components.first(where: { $0.id == draft.componentId })?.designator ?? "Pin"
                let targetName = circuit.components.first(where: { $0.id == componentId })?.designator ?? "Pin"
                lastConnectedWireDescription = "✅ Connected \(startName) → \(targetName)"
            }
            wireDraftStartPin = nil
            wireDraftCurrentPoint = nil
            wireDraftTargetPinId = nil
        } else {
            // Start wiring from this pin
            wireDraftStartPin = (componentId, pin)
            if let startComp = circuit.components.first(where: { $0.id == componentId }) {
                let p = startComp.absolutePinPosition(pinIndex: pin.index)
                wireDraftCurrentPoint = CGPoint(x: p.x, y: p.y)
                lastConnectedWireDescription = "⚡️ Wiring from \(startComp.designator) '\(pin.name)' — release on another terminal, or on a wire to join it"
            }
        }
    }

    /// Drops the draft onto an existing wire, joining that net with a T-junction.
    public func completeWireDraft(ontoWire wire: Wire, at point: Point2D) {
        guard let draft = wireDraftStartPin else { return }
        let endPin = tapEndPin(for: wire, near: point)
        if !hasWire(between: draft.pin.id, and: endPin) {
            circuit.wires.append(Wire(startPinId: draft.pin.id, endPinId: endPin, waypoints: [point]))
            solver.rebuildNetlist()
            let target = circuit.components.first(where: { c in c.pins.contains { $0.id == endPin } })?.designator ?? "wire"
            lastConnectedWireDescription = "✅ Tapped into \(target)'s net"
        }
        wireDraftStartPin = nil
        wireDraftCurrentPoint = nil
        wireDraftTargetPinId = nil
        objectWillChange.send()
    }

    public func cancelWiring() {
        wireDraftStartPin = nil
        wireDraftCurrentPoint = nil
        wireDraftTargetPinId = nil
        lastConnectedWireDescription = nil
    }

    public func diagnoseCircuit() -> CircuitDiagnosticReport {
        return CircuitDiagnostics.diagnose(circuit: circuit, solver: solver)
    }

    // MARK: - Preset lab circuits

    public static func createStarterCircuit() -> Circuit {
        // Half-wave rectifier with a smoothing capacitor.
        let vsrc = CircuitComponent(kind: .acVoltageSource, designator: "V1", position: Point2D(x: 140, y: 240), value: 9.0, secondaryValue: 50.0)
        let d1 = CircuitComponent(kind: .diode, designator: "D1", position: Point2D(x: 280, y: 160))
        let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 420, y: 240), rotation: 90, value: 1000.0)
        let c1 = CircuitComponent(kind: .capacitor, designator: "C1", position: Point2D(x: 360, y: 240), rotation: 90, value: 47e-6)
        let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 280, y: 340))

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
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 160, y: 240), value: 12.0)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 280, y: 160), value: 4.0)
            let r2 = CircuitComponent(kind: .resistor, designator: "R2", position: Point2D(x: 400, y: 240), rotation: 90, value: 6.0)
            let r3 = CircuitComponent(kind: .resistor, designator: "R3", position: Point2D(x: 480, y: 240), rotation: 90, value: 12.0)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 320, y: 340))

            let wires = [
                Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: r3.pins[0].id),
                Wire(startPinId: r2.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: r3.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
            ]
            circuit = Circuit(components: [v1, r1, r2, r3, gnd], wires: wires)

        case .theveninTheorem:
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 160, y: 240), value: 20.0)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 280, y: 160), value: 10.0)
            let r2 = CircuitComponent(kind: .resistor, designator: "R2", position: Point2D(x: 380, y: 240), rotation: 90, value: 40.0)
            let rl = CircuitComponent(kind: .resistor, designator: "R_LOAD", position: Point2D(x: 480, y: 240), rotation: 90, value: 8.0)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 320, y: 340))

            let wires = [
                Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: r2.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: rl.pins[0].id),
                Wire(startPinId: r2.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: rl.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
            ]
            circuit = Circuit(components: [v1, r1, r2, rl, gnd], wires: wires)

        case .maxPowerTransfer:
            // Potentiometer used as a variable load (track end A + wiper W) with meters on it.
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 160, y: 260), value: 12.0)
            let rs = CircuitComponent(kind: .resistor, designator: "R_SOURCE", position: Point2D(x: 280, y: 160), value: 100.0)
            let rl = CircuitComponent(kind: .potentiometer, designator: "R_LOAD", position: Point2D(x: 400, y: 160), value: 500.0, secondaryValue: 0.2)
            let am = CircuitComponent(kind: .ammeter, designator: "I1", position: Point2D(x: 400, y: 260), rotation: 90)
            let vm = CircuitComponent(kind: .voltmeter, designator: "U1", position: Point2D(x: 540, y: 160))
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 400, y: 380))

            let wires = [
                Wire(startPinId: v1.pins[0].id, endPinId: rs.pins[0].id),
                Wire(startPinId: rs.pins[1].id, endPinId: rl.pins[0].id),
                Wire(startPinId: rl.pins[2].id, endPinId: am.pins[0].id),
                Wire(startPinId: am.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: vm.pins[0].id, endPinId: rl.pins[2].id),
                Wire(startPinId: vm.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
            ]
            circuit = Circuit(components: [v1, rs, rl, am, vm, gnd], wires: wires)

        case .rlcResonance:
            let v1 = CircuitComponent(kind: .acVoltageSource, designator: "V1", position: Point2D(x: 140, y: 240), value: 10.0, secondaryValue: 1591.0)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 260, y: 160), value: 10.0)
            let l1 = CircuitComponent(kind: .inductor, designator: "L1", position: Point2D(x: 360, y: 160), value: 10e-3)
            let c1 = CircuitComponent(kind: .capacitor, designator: "C1", position: Point2D(x: 460, y: 240), rotation: 90, value: 1e-6)
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 300, y: 340))

            let wires = [
                Wire(startPinId: v1.pins[0].id, endPinId: r1.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: l1.pins[0].id),
                Wire(startPinId: l1.pins[1].id, endPinId: c1.pins[0].id),
                Wire(startPinId: c1.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
            ]
            circuit = Circuit(components: [v1, r1, l1, c1, gnd], wires: wires)

        case .fullWaveBridge:
            let v1 = CircuitComponent(kind: .acVoltageSource, designator: "V1", position: Point2D(x: 120, y: 240), value: 12.0, secondaryValue: 50.0)
            let d1 = CircuitComponent(kind: .diode, designator: "D1", position: Point2D(x: 260, y: 180))
            let d2 = CircuitComponent(kind: .diode, designator: "D2", position: Point2D(x: 360, y: 180))
            let d3 = CircuitComponent(kind: .diode, designator: "D3", position: Point2D(x: 260, y: 280))
            let d4 = CircuitComponent(kind: .diode, designator: "D4", position: Point2D(x: 360, y: 280))
            let c1 = CircuitComponent(kind: .electrolyticCapacitor, designator: "C_FILTER", position: Point2D(x: 460, y: 240), rotation: 90, value: 47e-6)
            let rLoad = CircuitComponent(kind: .resistor, designator: "R_LOAD", position: Point2D(x: 540, y: 240), rotation: 90, value: 1000.0)
            let vm = CircuitComponent(kind: .voltmeter, designator: "U_OUT", position: Point2D(x: 460, y: 340))
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 360, y: 380))

            let wires = [
                Wire(startPinId: v1.pins[0].id, endPinId: d1.pins[0].id),
                Wire(startPinId: d1.pins[0].id, endPinId: d3.pins[1].id),
                Wire(startPinId: v1.pins[1].id, endPinId: d2.pins[0].id),
                Wire(startPinId: d2.pins[0].id, endPinId: d4.pins[1].id),
                Wire(startPinId: d1.pins[1].id, endPinId: d2.pins[1].id),
                Wire(startPinId: d2.pins[1].id, endPinId: c1.pins[0].id),
                Wire(startPinId: c1.pins[0].id, endPinId: rLoad.pins[0].id),
                Wire(startPinId: d3.pins[0].id, endPinId: d4.pins[0].id),
                Wire(startPinId: d4.pins[0].id, endPinId: c1.pins[1].id),
                Wire(startPinId: c1.pins[1].id, endPinId: rLoad.pins[1].id),
                Wire(startPinId: c1.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: vm.pins[0].id, endPinId: c1.pins[0].id),
                Wire(startPinId: vm.pins[1].id, endPinId: c1.pins[1].id),
            ]
            circuit = Circuit(components: [v1, d1, d2, d3, d4, c1, rLoad, vm, gnd], wires: wires)

        case .ammeterVoltmeterOhmsLaw:
            // 12 V -> ammeter -> 120 ohm -> ground, voltmeter reading across the resistor.
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 140, y: 240), value: 12.0)
            let am = CircuitComponent(kind: .ammeter, designator: "A1", position: Point2D(x: 280, y: 160))
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 420, y: 160), value: 120.0)
            let vm = CircuitComponent(kind: .voltmeter, designator: "V2", position: Point2D(x: 350, y: 260))
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 500, y: 300))

            let wires = [
                Wire(startPinId: v1.pins[0].id, endPinId: am.pins[0].id),
                Wire(startPinId: am.pins[1].id, endPinId: r1.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: vm.pins[0].id, endPinId: am.pins[1].id),
                Wire(startPinId: vm.pins[1].id, endPinId: r1.pins[1].id),
                Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
            ]
            circuit = Circuit(components: [v1, am, r1, vm, gnd], wires: wires)

        case .potentiometerDivider:
            // Track across the supply, wiper feeds the load, probe reads the divided voltage.
            let v1 = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 160, y: 240), value: 5.0)
            let pot = CircuitComponent(kind: .potentiometer, designator: "RV1", position: Point2D(x: 320, y: 160), value: 10_000.0, secondaryValue: 0.5)
            let rl = CircuitComponent(kind: .resistor, designator: "R_LOAD", position: Point2D(x: 480, y: 240), rotation: 90, value: 2200.0)
            let probe = CircuitComponent(kind: .probe, designator: "P1", position: Point2D(x: 400, y: 260))
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 320, y: 300))

            let wires = [
                Wire(startPinId: v1.pins[0].id, endPinId: pot.pins[0].id),
                Wire(startPinId: pot.pins[1].id, endPinId: rl.pins[0].id),
                Wire(startPinId: pot.pins[2].id, endPinId: probe.pins[0].id),
                Wire(startPinId: rl.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: v1.pins[1].id, endPinId: gnd.pins[0].id),
            ]
            circuit = Circuit(components: [v1, pot, rl, probe, gnd], wires: wires)

        case .halfWaveRectifier:
            circuit = Self.createStarterCircuit()

        case .rcLowPassFilter:
            let vsrc = CircuitComponent(kind: .acVoltageSource, designator: "V1", position: Point2D(x: 160, y: 240), value: 5.0, secondaryValue: 1000.0)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 280, y: 180), value: 1000.0)
            let c1 = CircuitComponent(kind: .capacitor, designator: "C1", position: Point2D(x: 380, y: 240), rotation: 90, value: 1e-7)
            let probe = CircuitComponent(kind: .probe, designator: "P1", position: Point2D(x: 460, y: 200))
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 280, y: 340))

            let wires = [
                Wire(startPinId: vsrc.pins[0].id, endPinId: r1.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: c1.pins[0].id),
                Wire(startPinId: c1.pins[0].id, endPinId: probe.pins[0].id),
                Wire(startPinId: c1.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id),
            ]
            circuit = Circuit(components: [vsrc, r1, c1, probe, gnd], wires: wires)

        case .ledSwitchCircuit:
            // Left-to-right series chain: source, switch, fuse, resistor, LED, ammeter, ground.
            let vsrc = CircuitComponent(kind: .dcVoltageSource, designator: "V1", position: Point2D(x: 160, y: 260), value: 9.0)
            let sw = CircuitComponent(kind: .switchSPST, designator: "SW1", position: Point2D(x: 260, y: 160), stateBool: true)
            let fu = CircuitComponent(kind: .fuse, designator: "F1", position: Point2D(x: 360, y: 160), value: 0.05, secondaryValue: 0.5, stateBool: true)
            let r1 = CircuitComponent(kind: .resistor, designator: "R1", position: Point2D(x: 460, y: 160), value: 330.0)
            let led = CircuitComponent(kind: .led, designator: "LED1", position: Point2D(x: 560, y: 160), ledColor: .green)
            let am = CircuitComponent(kind: .ammeter, designator: "A1", position: Point2D(x: 660, y: 160))
            let gnd = CircuitComponent(kind: .ground, designator: "GND", position: Point2D(x: 660, y: 260))

            let wires = [
                Wire(startPinId: vsrc.pins[0].id, endPinId: sw.pins[0].id),
                Wire(startPinId: sw.pins[1].id, endPinId: fu.pins[0].id),
                Wire(startPinId: fu.pins[1].id, endPinId: r1.pins[0].id),
                Wire(startPinId: r1.pins[1].id, endPinId: led.pins[0].id),
                Wire(startPinId: led.pins[1].id, endPinId: am.pins[0].id),
                Wire(startPinId: am.pins[1].id, endPinId: gnd.pins[0].id),
                Wire(startPinId: vsrc.pins[1].id, endPinId: gnd.pins[0].id),
            ]
            circuit = Circuit(components: [vsrc, sw, fu, r1, led, am, gnd], wires: wires)
        }

        selectedComponentId = nil
        selectedWireId = nil
        solver = MNASolver(circuit: circuit, timeStep: 1e-4)
        oscilloscopeChannelACompId = circuit.components.first(where: { $0.kind.isCapacitive || $0.kind.isJunctionDiode || $0.kind == .resistor })?.id
        oscilloscopeChannelBCompId = nil
        resetSimulation()
        lastConnectedWireDescription = "🧪 \(type.rawValue) loaded — every terminal is already wired"
    }


    // MARK: - Live instrument readout text

    /// The number an instrument face shows right now.
    public func readingText(for comp: CircuitComponent) -> String {
        switch comp.kind {
        case .ammeter, .galvanometer:
            return EngineeringFormatter.current(comp.runtimeReading)
        case .voltmeter:
            return EngineeringFormatter.voltage(comp.runtimeReading)
        case .ohmmeter:
            return EngineeringFormatter.resistance(comp.runtimeReading)
        case .wattmeter:
            return EngineeringFormatter.power(comp.runtimeReading)
        case .multimeter:
            switch MeterMode(rawValue: comp.modeIndex) ?? .voltage {
            case .voltage: return EngineeringFormatter.voltage(comp.runtimeReading)
            case .current: return EngineeringFormatter.current(comp.runtimeReading)
            case .resistance: return EngineeringFormatter.resistance(comp.runtimeReading)
            }
        case .probe:
            return EngineeringFormatter.voltage(comp.runtimeReading)
        case .switchSPST:
            return comp.stateBool ? "CLOSED" : "OPEN"
        case .fuse:
            return comp.stateBool ? EngineeringFormatter.current(comp.fuseRating) : "BLOWN"
        case .led:
            return comp.ledColor.rawValue.capitalized
        case .potentiometer, .rheostat:
            return EngineeringFormatter.resistance(comp.value * Self.wiperRatio(comp))
        default:
            return ""
        }
    }

    static func wiperRatio(_ comp: CircuitComponent) -> Double {
        MNASolver.wiperRatio(of: comp)
    }
}

/// Compact engineering units for instrument faces and part labels.
public enum EngineeringFormatter {
    public static func resistance(_ val: Double) -> String { units(val, "Ω") }
    public static func voltage(_ val: Double) -> String { units(val, "V") }
    public static func current(_ val: Double) -> String { units(val, "A") }
    public static func power(_ val: Double) -> String { units(val, "W") }
    public static func capacitance(_ val: Double) -> String { units(val, "F") }
    public static func inductance(_ val: Double) -> String { units(val, "H") }

    public static func units(_ val: Double, _ unit: String) -> String {
        let a = abs(val)
        guard a > 0 else { return "0 \(unit)" }
        if a >= 1e6 { return String(format: "%.3g M%@", a / 1e6, unit) }
        if a >= 1e3 { return String(format: "%.3g k%@", a / 1e3, unit) }
        if a >= 1 { return String(format: "%.3g %@", a, unit) }
        if a >= 1e-3 { return String(format: "%.3g m%@", a * 1e3, unit) }
        if a >= 1e-6 { return String(format: "%.3g µ%@", a * 1e6, unit) }
        if a >= 1e-9 { return String(format: "%.3g n%@", a * 1e9, unit) }
        if a >= 1e-12 { return String(format: "%.3g p%@", a * 1e12, unit) }
        return String(format: "%.3g %@", a, unit)
    }
}

extension CircuitComponent {
    /// Rated current of a fuse, defaulting to 1 A.
    public var fuseRating: Double { secondaryValue > 0 ? secondaryValue : 1.0 }
}

public enum PresetType: String, CaseIterable, Identifiable {
    case kvlKclVerification = "Lab 1: KVL & KCL Verification"
    case theveninTheorem = "Lab 2: Thevenin's & Norton's Theorem"
    case maxPowerTransfer = "Lab 3: Maximum Power Transfer"
    case rlcResonance = "Lab 4: Series RLC Resonance (1.59 kHz)"
    case fullWaveBridge = "Lab 5: Full-Wave Bridge Rectifier"
    case ammeterVoltmeterOhmsLaw = "Lab 6: Ohm's Law with Ammeter & Voltmeter"
    case potentiometerDivider = "Lab 7: Potentiometer as Potential Divider"
    case halfWaveRectifier = "Example: Half-Wave Rectifier"
    case rcLowPassFilter = "Example: RC Low-Pass Filter"
    case ledSwitchCircuit = "Example: Interactive LED & Switch"

    public var id: String { rawValue }
}
