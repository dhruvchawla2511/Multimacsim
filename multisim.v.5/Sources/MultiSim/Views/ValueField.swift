import SwiftUI
import MultiSimEngine

/// One editable number: type `4.7k`, `100u`, `10MEG` and press Return, nudge with the arrows,
/// or drag the slider and watch the circuit respond live.
struct ValueField: View {
    let spec: ParameterSpec
    let value: Double
    /// Called with the raw (unclamped) value; the view model clamps it and returns what it applied.
    let onChange: (Double) -> Void
    var warning: String? = nil

    @State private var text: String = ""
    @State private var isInvalid = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spec.label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($focused)
                    .onSubmit(commit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isInvalid ? Color.red : Color.clear, lineWidth: 1.5)
                    )

                if !spec.unit.isEmpty {
                    Text(spec.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .leading)
                }

                VStack(spacing: 0) {
                    Button { onChange(spec.stepped(from: value, up: true)) } label: {
                        Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
                    }
                    Button { onChange(spec.stepped(from: value, up: false)) } label: {
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(.borderless)
                .help(spec.usesESeries ? "Step to the next standard (E12) value" : "Step up / down")
            }

            Slider(value: sliderBinding, in: sliderBounds)
                .controlSize(.small)

            if isInvalid {
                Text("Not a number. Try 4.7k, 100u, 10MEG, 2.2n or 60.")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if let warning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("Allowed: \(EngineeringUnitParser.format(spec.range.lowerBound)) to \(EngineeringUnitParser.format(spec.range.upperBound)) \(spec.unit)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { text = EngineeringUnitParser.format(value) }
        // Follow outside changes (slider, stepper, preset load, another surface) unless the user is mid-typing.
        .onChange(of: value) { _, newValue in
            if !focused { text = EngineeringUnitParser.format(newValue); isInvalid = false }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        // Focus/blur with no edit must not re-apply the rounded display text.
        if text == EngineeringUnitParser.format(value) { isInvalid = false; return }
        if let parsed = EngineeringUnitParser.parse(text, unit: spec.unit) {
            isInvalid = false
            onChange(parsed)
            // Show what was actually applied (it may have been clamped).
            text = EngineeringUnitParser.format(spec.clamp(parsed))
        } else {
            isInvalid = true
            // Keep the bad text visible so it can be fixed; the circuit keeps its old value.
        }
    }

    // MARK: - Slider mapping (log for R/C/L/frequency, linear for voltages)

    private var sliderBounds: ClosedRange<Double> {
        spec.isLogarithmic
            ? log10(spec.sliderRange.lowerBound)...log10(spec.sliderRange.upperBound)
            : spec.sliderRange
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                if spec.isLogarithmic {
                    let t = log10(max(value, spec.sliderRange.lowerBound))
                    return min(max(t, sliderBounds.lowerBound), sliderBounds.upperBound)
                }
                return min(max(value, spec.sliderRange.lowerBound), spec.sliderRange.upperBound)
            },
            set: { raw in
                let v = spec.isLogarithmic ? pow(10.0, raw) : raw
                // Three significant digits keeps labels clean while dragging.
                onChange(Double(String(format: "%.3g", v)) ?? v)
            }
        )
    }
}
