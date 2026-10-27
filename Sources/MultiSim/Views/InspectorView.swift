import SwiftUI
import MultiSimEngine

/// The property inspector panel for fine-tuning component values, viewing live measurements, and circuit diagnostics.
public struct InspectorView: View {
    @ObservedObject var viewModel: CircuitEditorViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedComp = viewModel.circuit.components.first(where: { $0.id == viewModel.selectedComponentId }) {
                componentInspector(for: selectedComp)
            } else {
                circuitSummary
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 240)
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
                }
                Spacer()
                Button(action: { viewModel.rotateSelected() }) {
                    Image(systemName: "rotate.right")
                }
                .help("Rotate 90° (R)")

                Button(action: { viewModel.deleteSelected() }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .help("Delete (Backspace)")
            }

            Divider()

            // Live Measurements (DMM)
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE PROBE READINGS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Voltage:")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.3f V", comp.runtimeVoltageDrop))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }

                HStack {
                    Text("Current:")
                        .font(.caption)
                    Spacer()
                    Text(formatCurrent(comp.runtimeCurrent))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }

                HStack {
                    Text("Power:")
                        .font(.caption)
                    Spacer()
                    let p = abs(comp.runtimeVoltageDrop * comp.runtimeCurrent)
                    Text(formatPower(p))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
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

                switch comp.kind {
                case .resistor:
                    parameterRow(label: "Resistance (Ω):", value: Binding(
                        get: { comp.value },
                        set: { comp.value = $0; viewModel.solver.rebuildNetlist() }
                    ))

                case .capacitor:
                    parameterRow(label: "Capacitance (F):", value: Binding(
                        get: { comp.value },
                        set: { comp.value = $0; viewModel.solver.rebuildNetlist() }
                    ))

                case .inductor:
                    parameterRow(label: "Inductance (H):", value: Binding(
                        get: { comp.value },
                        set: { comp.value = $0; viewModel.solver.rebuildNetlist() }
                    ))

                case .dcVoltageSource:
                    parameterRow(label: "Voltage (V):", value: Binding(
                        get: { comp.value },
                        set: { comp.value = $0; viewModel.solver.rebuildNetlist() }
                    ))

                case .acVoltageSource:
                    parameterRow(label: "Peak Amplitude (V):", value: Binding(
                        get: { comp.value },
                        set: { comp.value = $0; viewModel.solver.rebuildNetlist() }
                    ))
                    parameterRow(label: "Frequency (Hz):", value: Binding(
                        get: { comp.secondaryValue },
                        set: { comp.secondaryValue = $0; viewModel.solver.rebuildNetlist() }
                    ))

                case .clockSource:
                    parameterRow(label: "Pulse Voltage (V):", value: Binding(
                        get: { comp.value },
                        set: { comp.value = $0; viewModel.solver.rebuildNetlist() }
                    ))
                    parameterRow(label: "Frequency (Hz):", value: Binding(
                        get: { comp.secondaryValue },
                        set: { comp.secondaryValue = $0; viewModel.solver.rebuildNetlist() }
                    ))

                case .vcvs:
                    parameterRow(label: "Voltage Gain (μ):", value: Binding(
                        get: { comp.value },
                        set: { comp.value = $0; viewModel.solver.rebuildNetlist() }
                    ))

                case .vccs:
                    parameterRow(label: "Transconductance gm (S):", value: Binding(
                        get: { comp.value },
                        set: { comp.value = $0; viewModel.solver.rebuildNetlist() }
                    ))

                case .switchSPST:
                    Toggle("Closed", isOn: Binding(
                        get: { comp.stateBool },
                        set: { comp.stateBool = $0 }
                    ))
                    .toggleStyle(.switch)

                case .led:
                    Picker("LED Color", selection: Binding(
                        get: { comp.ledColor },
                        set: { comp.ledColor = $0 }
                    )) {
                        ForEach(LEDColor.allCases, id: \.self) { color in
                            Text(color.rawValue.capitalized).tag(color)
                        }
                    }

                case .zenerDiode:
                    parameterRow(label: "Zener Breakdown (V):", value: Binding(
                        get: { comp.secondaryValue },
                        set: { comp.secondaryValue = $0 }
                    ))

                case .bjtNPN, .bjtPNP:
                    parameterRow(label: "Current Gain (β / hFE):", value: Binding(
                        get: { comp.secondaryValue },
                        set: { comp.secondaryValue = $0 }
                    ))

                default:
                    Text("Standard ideal component model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func parameterRow(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Circuit Summary

    private var circuitSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CIRCUIT OVERVIEW")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                summaryRow(title: "Components", value: "\(viewModel.circuit.components.count)")
                summaryRow(title: "Wires", value: "\(viewModel.circuit.wires.count)")
                summaryRow(title: "Electrical Nodes", value: "\(viewModel.solver.totalNodes)")
                summaryRow(title: "Sim Time", value: String(format: "%.4f s", viewModel.currentSimulationTime))
                summaryRow(title: "Engine Status", value: viewModel.isSimulating ? "Running" : "Paused")
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("Tip: Click any component terminal pin to route orthogonal wires. Click switches to toggle live.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
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

    private func formatCurrent(_ a: Double) -> String {
        let absA = abs(a)
        if absA >= 1.0 { return String(format: "%.3f A", a) }
        if absA >= 1e-3 { return String(format: "%.3f mA", a * 1e3) }
        if absA >= 1e-6 { return String(format: "%.3f µA", a * 1e6) }
        return String(format: "%.3f nA", a * 1e9)
    }

    private func formatPower(_ w: Double) -> String {
        if w >= 1.0 { return String(format: "%.3f W", w) }
        if w >= 1e-3 { return String(format: "%.3f mW", w * 1e3) }
        if w >= 1e-6 { return String(format: "%.3f µW", w * 1e6) }
        return String(format: "%.3f nW", w * 1e9)
    }
}
