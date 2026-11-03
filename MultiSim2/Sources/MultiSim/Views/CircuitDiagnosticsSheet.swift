import SwiftUI
import MultiSimEngine

/// Diagnostic inspection sheet displaying circuit health checks, open pin warnings, and complete DC Operating Point table.
public struct CircuitDiagnosticsSheet: View {
    @ObservedObject var viewModel: CircuitEditorViewModel
    @Environment(\.dismiss) private var dismiss

    private var report: CircuitDiagnosticReport {
        viewModel.diagnoseCircuit()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Circuit Simulation Diagnostics", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            // Health Status Banner
            HStack(spacing: 12) {
                Image(systemName: report.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(report.isHealthy ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(report.statusMessage)
                        .font(.system(size: 12, weight: .bold))
                    Text(report.isClosedLoop ? "Current is actively circulating through circuit branches." : "Circuit is open. Connect all terminals to complete the loop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(report.isHealthy ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Open / Floating Pins Warning
            if !report.openPins.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UNCONNECTED / FLOATING TERMINALS (\(report.openPins.count)):")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)

                    ForEach(report.openPins.indices, id: \.self) { idx in
                        let pin = report.openPins[idx]
                        Text("• \(pin.component) pin '\(pin.pin)' is unconnected")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // DC Operating Point (.OP) Table
            VStack(alignment: .leading, spacing: 6) {
                Text("DC OPERATING POINT (.OP) NODE VOLTAGES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(report.nodeVoltages.keys.sorted(), id: \.self) { nodeIdx in
                            HStack {
                                Text(nodeIdx == 0 ? "Node 0 (GND)" : "Node \(nodeIdx)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Spacer()
                                Text(String(format: "%.4f V", report.nodeVoltages[nodeIdx] ?? 0.0))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(nodeIdx == 0 ? .secondary : .primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            // Component Branches Table
            VStack(alignment: .leading, spacing: 6) {
                Text("BRANCH CURRENTS & POWER DISSIPATION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(report.branchCurrents, id: \.designator) { branch in
                            HStack {
                                Text(branch.designator)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(width: 60, alignment: .leading)

                                Text(String(format: "V: %.3f V", branch.voltage))
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 90, alignment: .leading)

                                Text("I: \(formatCurrent(branch.current))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 100, alignment: .leading)

                                Spacer()

                                let power = abs(branch.voltage * branch.current)
                                Text("P: \(formatPower(power))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(18)
        .frame(width: 540, height: 500)
    }

    private func formatCurrent(_ a: Double) -> String {
        let absA = abs(a)
        if absA >= 1.0 { return String(format: "%.3f A", a) }
        if absA >= 1e-3 { return String(format: "%.2f mA", a * 1e3) }
        if absA >= 1e-6 { return String(format: "%.2f µA", a * 1e6) }
        return String(format: "%.2f nA", a * 1e9)
    }

    private func formatPower(_ w: Double) -> String {
        if w >= 1.0 { return String(format: "%.3f W", w) }
        if w >= 1e-3 { return String(format: "%.2f mW", w * 1e3) }
        return String(format: "%.2f µW", w * 1e6)
    }
}
