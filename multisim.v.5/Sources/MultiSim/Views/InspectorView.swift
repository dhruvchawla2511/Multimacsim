import SwiftUI
import MultiSimEngine

/// The property inspector panel for fine-tuning component values, viewing live measurements, and circuit diagnostics.
public struct InspectorView: View {
    @ObservedObject var viewModel: CircuitEditorViewModel

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let selectedComp = viewModel.circuit.components.first(where: { $0.id == viewModel.selectedComponentId }) {
                    componentInspector(for: selectedComp)
                } else {
                    circuitSummary
                }
            }
            .padding(12)
        }
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .leading)
    }

    // MARK: - Selected Component Inspector

    private func componentInspector(for comp: CircuitComponent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(comp.designator)
                        .font(.title3.bold())
                    Text(comp.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(comp.kind.category.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(comp.kind.isInstrument ? Color.orange : Color.accentColor)
                }
                Spacer()
                Button(action: { viewModel.rotateSelected() }) {
                    Image(systemName: "rotate.right")
                }
                .help("Rotate 90° (R) — leads and wires re-route automatically")

                Button(action: { viewModel.deleteSelected() }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .help("Delete (Backspace)")
            }

            Divider()

            // Live Measurements
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE PROBE READINGS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                if comp.kind.showsLiveReading {
                    readingRow(label: liveReadingLabel(for: comp), value: viewModel.readingText(for: comp))
                }

                measurementRow(title: "Voltage:", value: EngineeringFormatter.voltage(comp.runtimeVoltageDrop))
                measurementRow(title: "Current:", value: EngineeringFormatter.current(comp.runtimeCurrent))
                measurementRow(title: "Power:", value: EngineeringFormatter.power(abs(comp.runtimeVoltageDrop * comp.runtimeCurrent)))

                if comp.kind == .galvanometer {
                    let deflection = MNASolver.galvanometerDeflection(of: comp)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Needle deflection: \(Int(deflection * 100))% of full scale")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ProgressView(value: deflection)
                            .tint(deflection > 0.95 ? .red : .orange)
                    }
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Divider()

            // Connections
            VStack(alignment: .leading, spacing: 6) {
                Text("TERMINALS & CONNECTIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                let wired = connectedPinIds
                ForEach(comp.pins) { pin in
                    HStack(spacing: 6) {
                        Image(systemName: wired.contains(pin.id) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(wired.contains(pin.id) ? Color.green : Color.orange)
                        Text(pin.name)
                            .font(.caption)
                        Spacer()
                        let node = viewModel.solver.pinToNode[pin.id] ?? 0
                        Text(node == 0 ? "GND (0V)" : "Node \(node)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if comp.pins.contains(where: { !wired.contains($0.id) }) {
                    Text("Drag this part until a terminal touches another terminal or a wire — it snaps and wires itself.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Divider()

            // Parameter Editor
            VStack(alignment: .leading, spacing: 8) {
                Text("PARAMETERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                parameterEditor(for: comp)
            }
        }
    }

    // MARK: - Parameter editors

    @ViewBuilder
    private func parameterEditor(for comp: CircuitComponent) -> some View {
        // Mode selectors first - they change what the other fields mean.
        if comp.kind == .multimeter {
            Picker("Measurement Mode", selection: binding(forModeOf: comp)) {
                ForEach(MeterMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
        }

        if comp.kind == .functionGenerator {
            Picker("Waveform", selection: binding(forModeOf: comp)) {
                ForEach(GeneratorWaveform.allCases, id: \.self) { wave in
                    Text(wave.label).tag(wave.rawValue)
                }
            }
        }

        if comp.kind == .switchSPST {
            Toggle("Contacts closed", isOn: Binding(
                get: { comp.stateBool },
                set: { comp.stateBool = $0; viewModel.refreshAfterEdit() }
            ))
            .toggleStyle(.switch)
        }

        if comp.kind == .fuse {
            HStack {
                Text(comp.stateBool ? "Fuse intact" : "Fuse blown")
                    .font(.caption)
                    .foregroundStyle(comp.stateBool ? Color.green : Color.red)
                Spacer()
                Button("Reset all fuses") {
                    viewModel.solver.resetFuses()
                }
                .controlSize(.small)
            }
        }

        if comp.kind == .led {
            Picker("LED Color", selection: Binding(
                get: { comp.ledColor },
                set: { comp.ledColor = $0; viewModel.refreshAfterEdit() }
            )) {
                ForEach(LEDColor.allCases, id: \.self) { color in
                    Text(color.rawValue.capitalized).tag(color)
                }
            }
        }

        // Every editable number is a ValueField: unit-aware text entry, E12 stepper and a live slider.
        if let spec = comp.kind.parameterSpec(.primary) {
            ValueField(spec: spec, value: comp.value) { newValue in
                _ = viewModel.setParameter(componentId: comp.id, slot: .primary, to: newValue)
            }
            .id("\(comp.id)-primary")
        }

        if let secondary = comp.kind.secondaryParameterLabel {
            if comp.kind == .potentiometer || comp.kind == .rheostat {
                wiperSlider(label: secondary, comp: comp)
            } else if let spec = comp.kind.parameterSpec(.secondary) {
                ValueField(
                    spec: spec,
                    value: comp.secondaryValue,
                    onChange: { newValue in
                        _ = viewModel.setParameter(componentId: comp.id, slot: .secondary, to: newValue)
                    },
                    warning: comp.sampleWarning(timeStep: viewModel.solver.timeStep)
                )
                .id("\(comp.id)-secondary")
            }
        }

        if comp.kind == .potentiometer {
            Text("A = track end, B = track end, W = wiper. Wire A and B across the supply and take the output from W for a potential divider; wire A and W (or B and W) for a variable resistor.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if comp.kind == .wattmeter {
            Text("CC+/CC- go in series with the load. PC+/PC- go across it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if comp.kind == .ammeter {
            Text("Ammeters belong in series - drop it into the line. Its tiny burden resistance keeps the circuit unchanged.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if comp.kind == .voltmeter {
            Text("Voltmeters belong across the part they measure. The very high input resistance means no current is stolen.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if comp.kind == .ohmmeter {
            Text("Connect the ohmmeter across the resistor under test - it pushes its own small test current through it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if comp.kind.parameterSpec(.primary) == nil && comp.kind.secondaryParameterLabel == nil && comp.kind != .led && comp.kind != .switchSPST {
            Text("Ideal model - nothing to set. Just wire it in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func wiperSlider(label: String, comp: CircuitComponent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(MNASolver.wiperRatio(of: comp) * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            Slider(value: Binding(
                get: { MNASolver.wiperRatio(of: comp) },
                set: { viewModel.setWiper(componentId: comp.id, to: $0) }
            ), in: 0...1)
            Text("Live: \(EngineeringFormatter.resistance(comp.value * MNASolver.wiperRatio(of: comp))) from A to W")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(forModeOf comp: CircuitComponent) -> Binding<Int> {
        Binding(get: { comp.modeIndex }, set: {
            comp.modeIndex = $0
            viewModel.solver.rebuildNetlist()
            viewModel.refreshAfterEdit()
        })
    }

    private func liveReadingLabel(for comp: CircuitComponent) -> String {
        switch comp.kind {
        case .ammeter, .galvanometer: return "Measured current"
        case .voltmeter: return "Measured voltage"
        case .ohmmeter: return "Measured resistance"
        case .wattmeter: return "Measured power"
        case .probe: return "Probe voltage"
        case .multimeter:
            switch MeterMode(rawValue: comp.modeIndex) ?? .voltage {
            case .voltage: return "DMM voltage"
            case .current: return "DMM current"
            case .resistance: return "DMM resistance"
            }
        default: return "Reading"
        }
    }

    private func readingRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
        }
    }

    private func measurementRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }

    private var connectedPinIds: Set<UUID> {
        var ids = Set<UUID>()
        for wire in viewModel.circuit.wires {
            ids.insert(wire.startPinId)
            ids.insert(wire.endPinId)
        }
        return ids
    }

    // MARK: - Circuit Summary

    private var circuitSummary: some View {
        let unconnected = viewModel.circuit.components.reduce(0) { partial, comp in
            partial + comp.pins.filter { !connectedPinIds.contains($0.id) }.count
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("CIRCUIT OVERVIEW")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                summaryRow(title: "Components", value: "\(viewModel.circuit.components.count)")
                summaryRow(title: "Wires", value: "\(viewModel.circuit.wires.count)")
                summaryRow(title: "Electrical Nodes", value: "\(viewModel.solver.totalNodes)")
                summaryRow(title: "Open Terminals", value: unconnected == 0 ? "none ✓" : "\(unconnected) ⚠️")
                summaryRow(title: "Sim Time", value: String(format: "%.4f s", viewModel.currentSimulationTime))
                summaryRow(title: "Engine Status", value: viewModel.isSimulating ? "Running" : "Paused")
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 6) {
                Button(action: { viewModel.autoConnectFacingPins() }) {
                    Label("Auto-Connect Facing Terminals", systemImage: "link")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: { viewModel.snapAllToGrid() }) {
                    Label("Snap Everything to Grid", systemImage: "grid")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Nothing is selected. Click a part to edit it, drag it near another part to connect, or pick a lab example from the left panel.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }
}
