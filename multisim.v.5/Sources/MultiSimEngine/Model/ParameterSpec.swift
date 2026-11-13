import Foundation

/// Describes one editable number on a part: its unit, legal range, and how a slider should sweep it.
public struct ParameterSpec: Sendable, Equatable {
    public let label: String
    public let unit: String
    /// Hard limits enforced on every edit.
    public let range: ClosedRange<Double>
    /// Range covered by the live slider (narrower than `range` so it stays usable).
    public let sliderRange: ClosedRange<Double>
    /// True for values that span decades (R, C, L, frequency).
    public let isLogarithmic: Bool
    /// Component values come in preferred series (E12) so the stepper snaps to real parts.
    public let usesESeries: Bool

    public func clamp(_ v: Double) -> Double { min(max(v, range.lowerBound), range.upperBound) }

    /// Increment for the stepper on linear parameters (1-2-5 sequence, about 50 steps across the slider).
    public var linearStep: Double {
        let raw = (sliderRange.upperBound - sliderRange.lowerBound) / 50.0
        guard raw > 0 else { return 1 }
        let e = floor(log10(raw) + 1e-12)
        let m = raw / pow(10.0, e)
        let nice: Double = m < 1.5 ? 1 : (m < 3.5 ? 2 : (m < 7.5 ? 5 : 10))
        return nice * pow(10.0, e)
    }

    /// Value after one stepper click. E-series parts jump to the next standard value; others move by `linearStep`.
    public func stepped(from current: Double, up: Bool) -> Double {
        let next: Double
        if usesESeries {
            next = ESeries.step(from: max(current, range.lowerBound), up: up)
        } else if isLogarithmic {
            next = current * (up ? 1.2 : 1.0 / 1.2)
        } else {
            next = current + (up ? linearStep : -linearStep)
        }
        return clamp(Double(String(format: "%.4g", next)) ?? next)
    }
}

public enum ParameterSlot: Sendable { case primary, secondary }

extension ComponentKind {
    /// Spec for the primary or secondary field, or nil when the slot is not a plain number
    /// (e.g. the potentiometer wiper has its own slider).
    public func parameterSpec(_ slot: ParameterSlot) -> ParameterSpec? {
        switch slot {
        case .primary:
            let label = primaryParameterLabel
            switch self {
            case .ground, .probe, .diode, .schottkyDiode, .led, .zenerDiode, .opAmp, .switchSPST,
                 .logicAND, .logicOR, .logicNOT, .logicNAND, .logicNOR, .logicXOR, .logicXNOR, .logicBuffer:
                return nil
            case .resistor, .rheostat, .lamp, .thermistor, .photoResistor, .potentiometer, .galvanometer:
                return ParameterSpec(label: label, unit: "Ω", range: 1e-3...1e9, sliderRange: 1...1e6, isLogarithmic: true, usesESeries: true)
            case .fuse, .ammeter, .wattmeter:
                return ParameterSpec(label: label, unit: "Ω", range: 1e-6...1e3, sliderRange: 1e-3...10, isLogarithmic: true, usesESeries: false)
            case .voltmeter, .multimeter:
                return ParameterSpec(label: label, unit: "Ω", range: 1e3...1e12, sliderRange: 1e5...1e9, isLogarithmic: true, usesESeries: false)
            case .capacitor, .electrolyticCapacitor, .trimmerCapacitor:
                return ParameterSpec(label: label, unit: "F", range: 1e-12...1, sliderRange: 1e-11...1e-2, isLogarithmic: true, usesESeries: true)
            case .inductor:
                return ParameterSpec(label: label, unit: "H", range: 1e-9...100, sliderRange: 1e-6...10, isLogarithmic: true, usesESeries: true)
            case .dcVoltageSource:
                // Negative allowed: flips polarity.
                return ParameterSpec(label: label, unit: "V", range: -1000...1000, sliderRange: -24...24, isLogarithmic: false, usesESeries: false)
            case .acVoltageSource, .clockSource, .functionGenerator:
                return ParameterSpec(label: label, unit: "V", range: 0...1000, sliderRange: 0...50, isLogarithmic: false, usesESeries: false)
            case .dcCurrentSource:
                return ParameterSpec(label: label, unit: "A", range: -10...10, sliderRange: -0.1...0.1, isLogarithmic: false, usesESeries: false)
            case .ohmmeter:
                return ParameterSpec(label: label, unit: "A", range: 1e-9...1, sliderRange: 1e-6...1e-2, isLogarithmic: true, usesESeries: false)
            case .vcvs:
                return ParameterSpec(label: label, unit: "", range: -1e6...1e6, sliderRange: -100...100, isLogarithmic: false, usesESeries: false)
            case .vccs:
                return ParameterSpec(label: label, unit: "S", range: -100...100, sliderRange: -1...1, isLogarithmic: false, usesESeries: false)
            case .bjtNPN, .bjtPNP:
                return nil
            }
        case .secondary:
            guard let label = secondaryParameterLabel else { return nil }
            switch self {
            case .acVoltageSource, .clockSource, .functionGenerator:
                return ParameterSpec(label: label, unit: "Hz", range: 1e-3...1e6, sliderRange: 1...1e4, isLogarithmic: true, usesESeries: true)
            case .potentiometer, .rheostat:
                return nil   // dedicated wiper slider
            case .fuse:
                return ParameterSpec(label: label, unit: "A", range: 1e-3...1e3, sliderRange: 0.01...10, isLogarithmic: true, usesESeries: false)
            case .thermistor:
                return ParameterSpec(label: label, unit: "°C", range: -50...300, sliderRange: -20...150, isLogarithmic: false, usesESeries: false)
            case .photoResistor:
                return ParameterSpec(label: label, unit: "lux", range: 0.1...1e5, sliderRange: 0.1...1e4, isLogarithmic: true, usesESeries: false)
            case .galvanometer:
                return ParameterSpec(label: label, unit: "A", range: 1e-9...1, sliderRange: 1e-6...1e-1, isLogarithmic: true, usesESeries: false)
            case .wattmeter:
                return ParameterSpec(label: label, unit: "Ω", range: 1...1e12, sliderRange: 1e3...1e9, isLogarithmic: true, usesESeries: false)
            case .zenerDiode:
                return ParameterSpec(label: label, unit: "V", range: 1...200, sliderRange: 2...24, isLogarithmic: false, usesESeries: false)
            case .bjtNPN, .bjtPNP:
                return ParameterSpec(label: label, unit: "", range: 1...1000, sliderRange: 20...500, isLogarithmic: true, usesESeries: false)
            default:
                return nil
            }
        }
    }
}

/// Preferred-value series for the stepper buttons.
public enum ESeries {
    public static let e12: [Double] = [1.0, 1.2, 1.5, 1.8, 2.2, 2.7, 3.3, 3.9, 4.7, 5.6, 6.8, 8.2]

    /// Next (`up == true`) or previous standard value strictly beyond `v`.
    public static func step(from v: Double, up: Bool) -> Double {
        guard v > 0, v.isFinite else { return up ? 1.0 : 1e-3 }
        let exponent = floor(log10(v) + 1e-12)
        let eps = 1e-6
        var candidates: [Double] = []
        for d in [-1.0, 0.0, 1.0] {
            for s in e12 { candidates.append(s * pow(10.0, exponent + d)) }
        }
        let pick = up ? candidates.filter { $0 > v * (1 + eps) }.min()
                      : candidates.filter { $0 < v * (1 - eps) }.max()
        let raw = pick ?? v
        return Double(String(format: "%.3g", raw)) ?? raw
    }
}

extension CircuitComponent {
    /// Warns when a source frequency is too high for the fixed solver step to resolve (needs >= 20 samples/cycle).
    public func sampleWarning(timeStep: Double) -> String? {
        guard kind.isVoltageSourceType, kind != .dcVoltageSource, secondaryValue > 0, timeStep > 0 else { return nil }
        let samples = 1.0 / (secondaryValue * timeStep)
        guard samples < 20 else { return nil }
        let maxFreq = 1.0 / (20.0 * timeStep)
        return String(format: "Only %.1f solver samples per cycle - waveform and resonance will be distorted. Stay under %.0f Hz at this step size.", samples, maxFreq)
    }
}
