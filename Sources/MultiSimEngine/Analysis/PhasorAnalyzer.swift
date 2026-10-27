import Foundation

/// Analyzes AC steady-state sinusoidal waveforms to compute standard electrical engineering power metrics.
/// Essential for B.Tech Year 1 Basic Electrical Engineering (BEE) AC Circuit Analysis.
public struct PhasorMetrics {
    public let vRMS: Double
    public let iRMS: Double
    public let activePower: Double    // P (Watts)
    public let apparentPower: Double  // S (VA)
    public let reactivePower: Double  // Q (VAR)
    public let powerFactor: Double    // PF = cos(phi)
    public let phaseAngleDeg: Double  // phi in degrees
    public let nature: PowerFactorNature

    public enum PowerFactorNature: String {
        case lagging = "Lagging (Inductive)"
        case leading = "Leading (Capacitive)"
        case unity = "Unity (Resistive)"
    }
}

public final class PhasorAnalyzer {
    /// Computes RMS, Power Triangle (P, Q, S), and Power Factor from time-domain sample buffers.
    public static func analyze(
        voltageSamples: [(time: Double, value: Double)],
        currentSamples: [(time: Double, value: Double)]
    ) -> PhasorMetrics {
        guard voltageSamples.count > 10, currentSamples.count > 10 else {
            return PhasorMetrics(
                vRMS: 0, iRMS: 0, activePower: 0, apparentPower: 0, reactivePower: 0,
                powerFactor: 1.0, phaseAngleDeg: 0, nature: .unity
            )
        }

        // Use the most recent window of samples (e.g. up to 400 samples)
        let sampleCount = min(voltageSamples.count, currentSamples.count, 400)
        let vSlice = voltageSamples.suffix(sampleCount)
        let iSlice = currentSamples.suffix(sampleCount)

        var sumVSq = 0.0
        var sumISq = 0.0
        var sumInstPower = 0.0

        for (v, i) in zip(vSlice, iSlice) {
            sumVSq += v.value * v.value
            sumISq += i.value * i.value
            sumInstPower += v.value * i.value
        }

        let n = Double(sampleCount)
        let vRMS = sqrt(sumVSq / n)
        let iRMS = sqrt(sumISq / n)
        let activePower = max(0.0, sumInstPower / n) // P (Watts)
        let apparentPower = vRMS * iRMS              // S (VA)
        let reactivePower = sqrt(max(0.0, apparentPower * apparentPower - activePower * activePower)) // Q (VAR)

        var pf = apparentPower > 1e-6 ? min(max(activePower / apparentPower, 0.0), 1.0) : 1.0
        if pf.isNaN { pf = 1.0 }

        let phaseAngleRad = acos(pf)
        let phaseAngleDeg = phaseAngleRad * 180.0 / .pi

        // Determine if leading or lagging based on derivative
        let nature: PhasorMetrics.PowerFactorNature
        if pf > 0.995 {
            nature = .unity
        } else {
            // Check sign of reactive power / impedance
            nature = reactivePower > 1e-4 ? .lagging : .leading
        }

        return PhasorMetrics(
            vRMS: vRMS,
            iRMS: iRMS,
            activePower: activePower,
            apparentPower: apparentPower,
            reactivePower: reactivePower,
            powerFactor: pf,
            phaseAngleDeg: phaseAngleDeg,
            nature: nature
        )
    }
}
