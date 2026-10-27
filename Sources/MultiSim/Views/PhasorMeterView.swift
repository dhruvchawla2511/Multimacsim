import SwiftUI
import MultiSimEngine

/// Phasor & AC Power Triangle virtual instrument for B.Tech Year 1 AC Analysis.
public struct PhasorMeterView: View {
    @ObservedObject var viewModel: CircuitEditorViewModel
    @Environment(\.dismiss) private var dismiss

    private var metrics: PhasorMetrics {
        PhasorAnalyzer.analyze(
            voltageSamples: viewModel.traceA.map { (time: $0.time, value: $0.voltage) },
            currentSamples: viewModel.traceB.map { (time: $0.time, value: $0.voltage) }
        )
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                Label("Phasor & AC Power Analyzer", systemImage: "dial.low.fill")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            HStack(spacing: 20) {
                // Vector Diagram Dial (Polar Plot)
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 170, height: 170)

                    // Axes
                    Path { p in
                        p.move(to: CGPoint(x: 15, y: 100))
                        p.addLine(to: CGPoint(x: 185, y: 100))
                        p.move(to: CGPoint(x: 100, y: 15))
                        p.addLine(to: CGPoint(x: 100, y: 185))
                    }
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)

                    // Voltage Vector (Reference along 0 deg / horizontal)
                    arrow(angleDeg: 0, length: 65, color: .red)

                    // Current Vector (rotated by -phi deg)
                    arrow(angleDeg: -metrics.phaseAngleDeg, length: 55, color: .cyan)

                    Text("V_ref")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                        .position(x: 175, y: 92)

                    Text("I_phase")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.cyan)
                        .position(x: 100 + 65 * cos(-metrics.phaseAngleDeg * .pi / 180),
                                  y: 100 + 65 * sin(-metrics.phaseAngleDeg * .pi / 180))
                }
                .frame(width: 200, height: 200)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Power Triangle Readouts
                VStack(alignment: .leading, spacing: 8) {
                    metricRow(title: "Voltage RMS (V_rms):", value: String(format: "%.2f V", metrics.vRMS), color: .red)
                    metricRow(title: "Current RMS (I_rms):", value: formatCurrent(metrics.iRMS), color: .cyan)
                    Divider()
                    metricRow(title: "Active Power (P):", value: String(format: "%.3f W", metrics.activePower), color: .green)
                    metricRow(title: "Reactive Power (Q):", value: String(format: "%.3f VAR", metrics.reactivePower), color: .orange)
                    metricRow(title: "Apparent Power (S):", value: String(format: "%.3f VA", metrics.apparentPower), color: .purple)
                    Divider()
                    metricRow(title: "Power Factor (cos φ):", value: String(format: "%.3f", metrics.powerFactor), color: .primary)
                    metricRow(title: "Phase Angle (φ):", value: String(format: "%.1f°", metrics.phaseAngleDeg), color: .primary)
                    metricRow(title: "Load Nature:", value: metrics.nature.rawValue, color: .accentColor)
                }
                .frame(width: 250)
            }

            Text("Tip: Assign Channel 1 probe to source voltage and Channel 2 probe to branch current for AC phasor calculations.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 530, height: 350)
    }

    private func arrow(angleDeg: Double, length: CGFloat, color: Color) -> some View {
        let rad = angleDeg * .pi / 180.0
        let endX = 100 + length * cos(rad)
        let endY = 100 + length * sin(rad)

        return Path { p in
            p.move(to: CGPoint(x: 100, y: 100))
            p.addLine(to: CGPoint(x: endX, y: endY))
        }
        .stroke(color, lineWidth: 2.5)
    }

    private func metricRow(title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func formatCurrent(_ a: Double) -> String {
        if a >= 1.0 { return String(format: "%.3f A", a) }
        return String(format: "%.2f mA", a * 1e3)
    }
}
