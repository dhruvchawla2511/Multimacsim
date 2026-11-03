import Foundation

/// Fast and robust parser/formatter for electrical engineering units and suffixes.
/// Supports standard prefixes: T, G, M/MEG, k, m, u/µ, n, p, f, and scientific notation (1e-6).
public final class EngineeringUnitParser {
    /// Parses an input string (e.g. "10k", "4.7k", "100u", "1M", "10MEG", "0.001", "1e-5") into a Double.
    public static func parse(_ text: String) -> Double? {
        var str = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "Ω", with: "")
            .replacingOccurrences(of: "ohm", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "V", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "F", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "H", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "A", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Hz", with: "", options: .caseInsensitive)

        if str.isEmpty { return nil }

        // Direct Double parse
        if let direct = Double(str) {
            return direct
        }

        // Check for SPICE "MEG" (Mega = 1e6) vs "m" (milli = 1e-3)
        let upper = str.uppercased()
        if upper.hasSuffix("MEG") {
            let numPart = String(str.dropLast(3))
            if let val = Double(numPart) { return val * 1e6 }
        }

        guard let lastChar = str.last else { return nil }
        let numPart = String(str.dropLast())
        guard let baseVal = Double(numPart) else { return nil }

        switch lastChar {
        case "T", "t": return baseVal * 1e12
        case "G", "g": return baseVal * 1e9
        case "M": return baseVal * 1e6
        case "k", "K": return baseVal * 1e3
        case "m": return baseVal * 1e-3
        case "u", "U", "µ": return baseVal * 1e-6
        case "n", "N": return baseVal * 1e-9
        case "p", "P": return baseVal * 1e-12
        case "f", "F": return baseVal * 1e-15
        default: return nil
        }
    }

    /// Formats a double value with appropriate engineering prefix.
    public static func format(_ val: Double) -> String {
        let absV = abs(val)
        if absV == 0.0 { return "0" }
        if absV >= 1e6 { return String(format: "%.3g MEG", val / 1e6) }
        if absV >= 1e3 { return String(format: "%.3g k", val / 1e3) }
        if absV >= 1.0 { return String(format: "%.3g", val) }
        if absV >= 1e-3 { return String(format: "%.3g m", val * 1e3) }
        if absV >= 1e-6 { return String(format: "%.3g u", val * 1e6) }
        if absV >= 1e-9 { return String(format: "%.3g n", val * 1e9) }
        if absV >= 1e-12 { return String(format: "%.3g p", val * 1e12) }
        return String(format: "%.3g", val)
    }
}
