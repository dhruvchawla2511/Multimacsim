import Foundation

/// Parser/formatter for electrical-engineering numbers such as `4.7k`, `4k7`, `100u`, `10MEG`, `2.2nF`, `60Hz`.
///
/// Prefix rules (documented because SPICE and everyday EE usage disagree):
///   `M` / `MEG` = mega (1e6), `m` = milli (1e-3), `k`/`K` = kilo, `u`/`µ` = micro, `n`, `p`, `f`, `G`, `T`.
/// Pass the expected `unit` (for example `"F"`, `"Hz"`, `"Ω"`) so a trailing unit symbol is dropped
/// instead of being mistaken for a prefix (`10pF` -> 10p, `5mV` -> 5m).
public enum EngineeringUnitParser {

    public static func parse(_ text: String, unit: String = "") -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00B5}", with: "u")   // micro sign
            .replacingOccurrences(of: "\u{03BC}", with: "u")   // greek mu
        guard !s.isEmpty else { return nil }

        s = stripTrailingUnit(s, unit: unit)
        guard !s.isEmpty else { return nil }

        if let v = Double(s) { return v.isFinite ? v : nil }

        // RKM notation: 4k7 = 4.7k, 2R2 = 2.2, 1M5 = 1.5M
        if let rkm = parseRKM(s) { return rkm }

        // SPICE "MEG"
        if s.uppercased().hasSuffix("MEG"), let base = Double(String(s.dropLast(3))) {
            return finite(base * 1e6)
        }

        guard let last = s.last, let base = Double(String(s.dropLast())),
              let mult = multiplier(for: last) else { return nil }
        return finite(base * mult)
    }

    /// Formats with a prefix and no unit, e.g. 4700 -> "4.7k", 1e-6 -> "1u". Round-trips through `parse`.
    public static func format(_ val: Double) -> String {
        let a = abs(val)
        if a == 0 { return "0" }
        let table: [(Double, String)] = [(1e12, "T"), (1e9, "G"), (1e6, "M"), (1e3, "k"), (1, ""),
                                         (1e-3, "m"), (1e-6, "u"), (1e-9, "n"), (1e-12, "p"), (1e-15, "f")]
        for (scale, prefix) in table where a >= scale * 0.9999999 {
            return String(format: "%.4g", val / scale) + prefix
        }
        return String(format: "%.4g", val)
    }

    // MARK: - Helpers

    private static func finite(_ v: Double) -> Double? { v.isFinite ? v : nil }

    private static func multiplier(for c: Character) -> Double? {
        switch c {
        case "T": return 1e12
        case "G", "g": return 1e9
        case "M": return 1e6
        case "k", "K": return 1e3
        case "m": return 1e-3
        case "u", "U": return 1e-6
        case "n", "N": return 1e-9
        case "p", "P": return 1e-12
        case "f": return 1e-15
        default: return nil
        }
    }

    private static func stripTrailingUnit(_ s: String, unit: String) -> String {
        var candidates: [String] = []
        let u = unit.trimmingCharacters(in: .whitespaces)
        if !u.isEmpty { candidates.append(u) }
        if u == "\u{03A9}" || u == "\u{2126}" || u.lowercased() == "ohm" { candidates.append(contentsOf: ["ohms", "ohm", "\u{03A9}", "\u{2126}"]) }
        // Longest first so "Hz" is tried before "H".
        for cand in candidates.sorted(by: { $0.count > $1.count }) {
            if s.lowercased().hasSuffix(cand.lowercased()) {
                let stripped = String(s.dropLast(cand.count))
                // Only strip when something numeric remains, so "F" alone is not eaten.
                if !stripped.isEmpty { return stripped }
            }
        }
        return s
    }

    private static func parseRKM(_ s: String) -> Double? {
        let chars = Array(s)
        guard chars.count >= 3 else { return nil }
        // find a single letter with digits on both sides
        for i in 1..<(chars.count - 1) where chars[i].isLetter {
            let left = String(chars[0..<i]), right = String(chars[(i + 1)...])
            guard left.allSatisfy({ $0.isNumber }), right.allSatisfy({ $0.isNumber }),
                  let whole = Double(left), let frac = Double("0." + right) else { return nil }
            let mult: Double
            if chars[i] == "R" || chars[i] == "r" { mult = 1 } else if let m = multiplier(for: chars[i]) { mult = m } else { return nil }
            return (whole + frac) * mult
        }
        return nil
    }
}
