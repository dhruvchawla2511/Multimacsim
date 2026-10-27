import Foundation

/// Defines all supported electronic component types and their parameter models.
public enum ComponentKind: String, Codable, CaseIterable {
    // Power & Ground
    case ground = "Ground"
    case dcVoltageSource = "DC Voltage Source"
    case acVoltageSource = "AC Voltage Source"
    case dcCurrentSource = "DC Current Source"
    case clockSource = "Clock / Pulse Source"

    // Passive
    case resistor = "Resistor"
    case capacitor = "Capacitor"
    case inductor = "Inductor"
    case potentiometer = "Potentiometer"
    case switchSPST = "Switch (SPST)"

    // Semiconductors
    case diode = "Diode"
    case led = "LED"
    case zenerDiode = "Zener Diode"
    case bjtNPN = "NPN Transistor"
    case bjtPNP = "PNP Transistor"

    // Active & ICs
    case opAmp = "Operational Amplifier"
    case vcvs = "VCVS (Voltage-Controlled Voltage Source)"
    case vccs = "VCCS (Voltage-Controlled Current Source)"
    case logicAND = "AND Gate"
    case logicOR = "OR Gate"
    case logicNOT = "NOT Gate"
    case logicNAND = "NAND Gate"
    case logicNOR = "NOR Gate"
    case logicXOR = "XOR Gate"
}

/// Represents the physical or logical pin of a component.
public struct Pin: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let index: Int
    public let name: String
    /// Relative offset from component center on the schematic canvas (in grid units).
    public var relativeX: Double
    public var relativeY: Double

    public init(id: UUID = UUID(), index: Int, name: String, relativeX: Double, relativeY: Double) {
        self.id = id
        self.index = index
        self.name = name
        self.relativeX = relativeX
        self.relativeY = relativeY
    }
}

/// Standard color for LEDs.
public enum LEDColor: String, Codable, CaseIterable {
    case red, green, blue, yellow, white

    public var forwardVoltage: Double {
        switch self {
        case .red: return 1.8
        case .yellow: return 2.1
        case .green: return 2.2
        case .blue: return 3.2
        case .white: return 3.3
        }
    }
}
