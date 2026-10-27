import SwiftUI
import MultiSimEngine

/// Virtual Dual-Channel Oscilloscope instrument panel for real-time waveform capture.
public struct OscilloscopeView: View {
    @ObservedObject var viewModel: CircuitEditorViewModel

    public var body: some View {
        VStack(spacing: 8) {
            // Header bar
            HStack {
                Label("Virtual Oscilloscope", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.showOscilloscope = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 12) {
                // Waveform Display Screen
                scopeScreen
                    .frame(height: 180)
                    .background(Color(red: 0.05, green: 0.08, blue: 0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                // Scope Controls Panel
                scopeControls
                    .frame(width: 220)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }

    // MARK: - CRT / LCD Waveform Screen

    private var scopeScreen: some View {
        GeometryReader { geo in
            ZStack {
                // Division Grid
                Canvas { context, size in
                    drawScopeGrid(context: context, size: size)
                }

                // Channel A Trace (Red)
                if viewModel.oscilloscopeChannelACompId != nil {
                    tracePath(trace: viewModel.traceA, voltsPerDiv: viewModel.oscilloscopeVoltsPerDivA, in: geo.size)
                        .stroke(Color.red, lineWidth: 1.8)
                }

                // Channel B Trace (Cyan)
                if viewModel.oscilloscopeChannelBCompId != nil {
                    tracePath(trace: viewModel.traceB, voltsPerDiv: viewModel.oscilloscopeVoltsPerDivB, in: geo.size)
                        .stroke(Color.cyan, lineWidth: 1.8)
                }

                // Live Measurement HUD
                VStack {
                    HStack {
                        if let compA = viewModel.circuit.components.first(where: { $0.id == viewModel.oscilloscopeChannelACompId }) {
                            Text("CH1: \(compA.designator)  \(String(format: "%.2f V", compA.runtimeVoltageDrop))")
                                .foregroundStyle(.red)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        Spacer()
                        if let compB = viewModel.circuit.components.first(where: { $0.id == viewModel.oscilloscopeChannelBCompId }) {
                            Text("CH2: \(compB.designator)  \(String(format: "%.2f V", compB.runtimeVoltageDrop))")
                                .foregroundStyle(.cyan)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
    }

    private func drawScopeGrid(context: GraphicsContext, size: CGSize) {
        let cols = 10
        let rows = 8
        let dx = size.width / CGFloat(cols)
        let dy = size.height / CGFloat(rows)

        var gridPath = Path()
        for i in 0...cols {
            let x = CGFloat(i) * dx
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
        }
        for j in 0...rows {
            let y = CGFloat(j) * dy
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
        }

        context.stroke(gridPath, with: .color(Color.green.opacity(0.15)), lineWidth: 0.8)

        // Center crosshair axes
        var centerPath = Path()
        centerPath.move(to: CGPoint(x: size.width / 2, y: 0))
        centerPath.addLine(to: CGPoint(x: size.width / 2, y: size.height))
        centerPath.move(to: CGPoint(x: 0, y: size.height / 2))
        centerPath.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(centerPath, with: .color(Color.green.opacity(0.35)), lineWidth: 1.2)
    }

    private func tracePath(trace: [(time: Double, voltage: Double)], voltsPerDiv: Double, in size: CGSize) -> Path {
        var path = Path()
        guard trace.count > 1 else { return path }

        let midY = size.height / 2.0
        let pixelsPerVolt = (size.height / 8.0) / CGFloat(voltsPerDiv)
        let timeSpan = viewModel.oscilloscopeTimeScale * 10.0 // 10 horizontal divisions
        guard timeSpan > 0 else { return path }

        let lastTime = trace.last?.time ?? 0.0
        let startTime = lastTime - timeSpan

        var started = false
        for sample in trace {
            if sample.time < startTime { continue }
            let x = CGFloat((sample.time - startTime) / timeSpan) * size.width
            let y = midY - CGFloat(sample.voltage) * pixelsPerVolt

            if !started {
                path.move(to: CGPoint(x: x, y: y))
                started = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    // MARK: - Controls Panel

    private var scopeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Channel A Selector
            VStack(alignment: .leading, spacing: 2) {
                Text("Channel 1 Probe")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
                Picker("", selection: $viewModel.oscilloscopeChannelACompId) {
                    Text("None").tag(UUID?.none)
                    ForEach(viewModel.circuit.components) { comp in
                        Text("\(comp.designator) (\(comp.kind.rawValue))").tag(UUID?.some(comp.id))
                    }
                }
                .labelsHidden()
            }

            // Channel B Selector
            VStack(alignment: .leading, spacing: 2) {
                Text("Channel 2 Probe")
                    .font(.caption2.bold())
                    .foregroundStyle(.cyan)
                Picker("", selection: $viewModel.oscilloscopeChannelBCompId) {
                    Text("None").tag(UUID?.none)
                    ForEach(viewModel.circuit.components) { comp in
                        Text("\(comp.designator) (\(comp.kind.rawValue))").tag(UUID?.some(comp.id))
                    }
                }
                .labelsHidden()
            }

            Divider()

            // Time/Div
            HStack {
                Text("Time/Div:")
                    .font(.caption2)
                Spacer()
                Picker("", selection: $viewModel.oscilloscopeTimeScale) {
                    Text("1 ms").tag(0.001)
                    Text("2 ms").tag(0.002)
                    Text("5 ms").tag(0.005)
                    Text("10 ms").tag(0.01)
                    Text("50 ms").tag(0.05)
                }
                .labelsHidden()
                .frame(width: 80)
            }

            // Volts/Div CH1
            HStack {
                Text("CH1 V/Div:")
                    .font(.caption2)
                Spacer()
                Picker("", selection: $viewModel.oscilloscopeVoltsPerDivA) {
                    Text("0.5 V").tag(0.5)
                    Text("1.0 V").tag(1.0)
                    Text("2.0 V").tag(2.0)
                    Text("5.0 V").tag(5.0)
                }
                .labelsHidden()
                .frame(width: 80)
            }
        }
    }
}
