import Foundation

/// Defines all supported electronic component types and their parameter models.
public enum ComponentKind: String, Codable, CaseIterable {
    // Power & Ground
    case ground = "Ground"
    case dcVoltageSource = "DC Voltage Source"
    case acVoltageSource = "AC Voltage Source"
    case dcCurrentSource = "DC Current Source"
    case clockSource = "Clock / Pulse Source"
    case functionGenerator = "Function Generator"

    // Measuring Instruments
    case ammeter = "Ammeter"
    case voltmeter = "Voltmeter"
    case galvanometer = "Galvanometer"
    case ohmmeter = "Ohmmeter"
    case wattmeter = "Wattmeter"
    case multimeter = "Multimeter (DMM)"

    // Passive
    case resistor = "Resistor"
    case capacitor = "Capacitor"
    case electrolyticCapacitor = "Electrolytic Capacitor"
    case trimmerCapacitor = "Trimmer Capacitor"
    case inductor = "Inductor"
    case potentiometer = "Potentiometer"
    case rheostat = "Rheostat"
    case switchSPST = "Switch (SPST)"
    case lamp = "Filament Lamp"
    case fuse = "Fuse"
    case thermistor = "Thermistor (NTC)"
    case photoResistor = "LDR (Photoresistor)"

    // Semiconductors
    case diode = "Diode"
    case led = "LED"
    case zenerDiode = "Zener Diode"
    case schottkyDiode = "Schottky Diode"
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
    case logicXNOR = "XNOR Gate"
    case logicBuffer = "Buffer"

    // Probes
    case probe = "Voltage Probe"
}

/// Grouping used by the palette so every part shows up on the same surface, in a fixed order.
public enum PartCategory: String, CaseIterable, Sendable {
    case instruments = "Measuring Instruments"
    case sources = "Sources & Ground"
    case passives = "Passives & Loads"
    case semiconductors = "Semiconductors"
    case analogLogic = "Analog & Logic ICs"
    case probes = "Probes & Test"
}

extension ComponentKind {
    public var category: PartCategory {
        switch self {
        case .ground, .dcVoltageSource, .acVoltageSource, .dcCurrentSource, .clockSource, .functionGenerator:
            return .sources
        case .ammeter, .voltmeter, .galvanometer, .ohmmeter, .wattmeter, .multimeter:
            return .instruments
        case .resistor, .capacitor, .electrolyticCapacitor, .trimmerCapacitor, .inductor,
             .potentiometer, .rheostat, .switchSPST, .lamp, .fuse, .thermistor, .photoResistor:
            return .passives
        case .diode, .led, .zenerDiode, .schottkyDiode, .bjtNPN, .bjtPNP:
            return .semiconductors
        case .opAmp, .vcvs, .vccs, .logicAND, .logicOR, .logicNOT, .logicNAND, .logicNOR,
             .logicXOR, .logicXNOR, .logicBuffer:
            return .analogLogic
        case .probe:
            return .probes
        }
    }

    /// Designator prefix used when the part is placed on the canvas.
    public var designatorPrefix: String {
        switch self {
        case .ground: return "GND"
        case .dcVoltageSource, .acVoltageSource: return "V"
        case .dcCurrentSource: return "I"
        case .clockSource: return "CLK"
        case .functionGenerator: return "FG"
        case .ammeter: return "A"
        case .voltmeter: return "V"
        case .galvanometer: return "G"
        case .ohmmeter: return "OHM"
        case .wattmeter: return "W"
        case .multimeter: return "DMM"
        case .resistor: return "R"
        case .capacitor, .electrolyticCapacitor, .trimmerCapacitor: return "C"
        case .inductor: return "L"
        case .potentiometer: return "POT"
        case .rheostat: return "RH"
        case .switchSPST: return "SW"
        case .lamp: return "LS"
        case .fuse: return "F"
        case .thermistor: return "TH"
        case .photoResistor: return "LDR"
        case .diode, .schottkyDiode: return "D"
        case .led: return "LED"
        case .zenerDiode: return "ZD"
        case .bjtNPN, .bjtPNP: return "Q"
        case .opAmp: return "U"
        case .vcvs: return "E"
        case .vccs: return "G"
        case .logicAND: return "U_AND"
        case .logicOR: return "U_OR"
        case .logicNOT: return "U_NOT"
        case .logicNAND: return "U_NAND"
        case .logicNOR: return "U_NOR"
        case .logicXOR: return "U_XOR"
        case .logicXNOR: return "U_XNOR"
        case .logicBuffer: return "U_BUF"
        case .probe: return "P"
        }
    }

    /// Short name shown in the palette row.
    public var paletteLabel: String {
        switch self {
        case .ground: return "Ground (0V)"
        case .dcVoltageSource: return "DC Voltage Source"
        case .acVoltageSource: return "AC Sine Source"
        case .dcCurrentSource: return "Current Source"
        case .clockSource: return "Clock Pulse"
        case .functionGenerator: return "Function Generator"
        case .ammeter: return "Ammeter (series A)"
        case .voltmeter: return "Voltmeter (parallel V)"
        case .galvanometer: return "Galvanometer"
        case .ohmmeter: return "Ohmmeter"
        case .wattmeter: return "Wattmeter"
        case .multimeter: return "Multimeter / DMM"
        case .resistor: return "Resistor"
        case .capacitor: return "Capacitor"
        case .electrolyticCapacitor: return "Electrolytic Cap"
        case .trimmerCapacitor: return "Trimmer Cap"
        case .inductor: return "Inductor"
        case .potentiometer: return "Potentiometer (3-wire)"
        case .rheostat: return "Rheostat (variable R)"
        case .switchSPST: return "SPST Switch"
        case .lamp: return "Filament Lamp"
        case .fuse: return "Fuse"
        case .thermistor: return "Thermistor NTC"
        case .photoResistor: return "LDR (light)"
        case .diode: return "Diode (1N4148)"
        case .led: return "LED"
        case .zenerDiode: return "Zener Diode"
        case .schottkyDiode: return "Schottky Diode"
        case .bjtNPN: return "NPN Transistor"
        case .bjtPNP: return "PNP Transistor"
        case .opAmp: return "Operational Amplifier"
        case .vcvs: return "VCVS (Voltage Controlled)"
        case .vccs: return "VCCS (Current Controlled)"
        case .logicAND: return "AND Gate"
        case .logicOR: return "OR Gate"
        case .logicNOT: return "NOT Inverter"
        case .logicNAND: return "NAND Gate"
        case .logicNOR: return "NOR Gate"
        case .logicXOR: return "XOR Gate"
        case .logicXNOR: return "XNOR Gate"
        case .logicBuffer: return "Buffer"
        case .probe: return "Voltage Probe"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .ground: return "arrow.down.to.line"
        case .dcVoltageSource: return "battery.100.bolt"
        case .acVoltageSource: return "waveform"
        case .clockSource: return "metronome"
        case .dcCurrentSource: return "arrow.up.circle"
        case .functionGenerator: return "waveform.path"
        case .ammeter: return "speedometer"
        case .voltmeter: return "bolt.horizontal"
        case .galvanometer: return "scalemass"
        case .ohmmeter: return "ruler"
        case .wattmeter: return "flame"
        case .multimeter: return "plusminus"
        case .resistor: return "alternatingcurrent"
        case .capacitor: return "pause"
        case .electrolyticCapacitor: return "capsule.portrait"
        case .trimmerCapacitor: return "slider.vertical.3"
        case .inductor: return "rotate.right"
        case .potentiometer: return "slider.horizontal.3"
        case .rheostat: return "dial.low.fill"
        case .switchSPST: return "switch.2"
        case .lamp: return "lightbulb"
        case .fuse: return "capsule"
        case .thermistor: return "thermometer"
        case .photoResistor: return "sun.max"
        case .diode: return "arrowtriangle.right.fill"
        case .led: return "lightbulb.fill"
        case .zenerDiode: return "bolt.fill"
        case .schottkyDiode: return "arrowtriangle.right.circle"
        case .bjtNPN: return "arrow.up.right.circle"
        case .bjtPNP: return "arrow.down.right.circle"
        case .opAmp: return "triangle.fill"
        case .vcvs: return "diamond.fill"
        case .vccs: return "diamond"
        case .logicAND: return "square.split.diagonal.2x2"
        case .logicOR: return "shield"
        case .logicNOT: return "circle.slash"
        case .logicNAND: return "square.split.diagonal"
        case .logicNOR: return "shield.slash"
        case .logicXOR: return "divide"
        case .logicXNOR: return "equals"
        case .logicBuffer: return "arrow.right.to.line"
        case .probe: return "pin"
        }
    }

    /// True when the part measures the circuit rather than being part of it.
    public var isInstrument: Bool {
        category == .instruments || self == .probe
    }

    /// Parts whose label shows a live measured value instead of a static rating.
    public var showsLiveReading: Bool {
        switch self {
        case .ammeter, .voltmeter, .galvanometer, .ohmmeter, .wattmeter, .multimeter, .probe:
            return true
        default:
            return false
        }
    }

    /// Two-terminal parts that behave as a plain resistance in the MNA matrix.
    public var isLinearResistive: Bool {
        switch self {
        case .resistor, .switchSPST, .potentiometer, .rheostat, .lamp, .fuse, .thermistor,
             .photoResistor, .ammeter, .voltmeter, .galvanometer:
            return true
        default:
            return false
        }
    }

    /// Two-terminal parts that behave as a capacitor (backward-Euler companion model).
    public var isCapacitive: Bool {
        self == .capacitor || self == .electrolyticCapacitor || self == .trimmerCapacitor
    }

    /// Parts conducting through a PN-junction style exponential model.
    public var isJunctionDiode: Bool {
        switch self {
        case .diode, .led, .schottkyDiode: return true
        default: return false
        }
    }

    /// Ideal voltage sources that need an auxiliary MNA variable.
    public var isVoltageSourceType: Bool {
        switch self {
        case .dcVoltageSource, .acVoltageSource, .clockSource, .functionGenerator: return true
        default: return false
        }
    }

    /// Digital gate parts.
    public var isLogicGate: Bool {
        switch self {
        case .logicAND, .logicOR, .logicNOT, .logicNAND, .logicNOR, .logicXOR, .logicXNOR, .logicBuffer:
            return true
        default:
            return false
        }
    }
}

/// Sensible starting parameter for a freshly placed part.
public struct PartDefaults: Sendable {
    public var value: Double
    public var secondaryValue: Double
    /// Closed switch / intact fuse.
    public var isClosed: Bool
    /// Waveform or meter mode index.
    public var modeIndex: Int

    public init(value: Double = 0, secondaryValue: Double = 0, isClosed: Bool = false, modeIndex: Int = 0) {
        self.value = value
        self.secondaryValue = secondaryValue
        self.isClosed = isClosed
        self.modeIndex = modeIndex
    }
}

extension ComponentKind {
    /// Values applied when the part is dropped on the canvas.
    public var partDefaults: PartDefaults {
        switch self {
        case .resistor: return PartDefaults(value: 1_000)
        case .capacitor: return PartDefaults(value: 1e-6)
        case .electrolyticCapacitor: return PartDefaults(value: 100e-6)
        case .trimmerCapacitor: return PartDefaults(value: 100e-12)
        case .inductor: return PartDefaults(value: 1e-3)
        case .dcVoltageSource: return PartDefaults(value: 5)
        case .acVoltageSource: return PartDefaults(value: 5, secondaryValue: 60)
        case .clockSource: return PartDefaults(value: 5, secondaryValue: 1_000)
        case .functionGenerator: return PartDefaults(value: 5, secondaryValue: 1_000)
        case .dcCurrentSource: return PartDefaults(value: 0.01)
        case .potentiometer: return PartDefaults(value: 10_000, secondaryValue: 0.5)
        case .rheostat: return PartDefaults(value: 1_000, secondaryValue: 0.5)
        case .switchSPST: return PartDefaults(isClosed: false)
        case .lamp: return PartDefaults(value: 10)
        case .fuse: return PartDefaults(value: 0.05, secondaryValue: 1.0, isClosed: true)
        case .thermistor: return PartDefaults(value: 10_000, secondaryValue: 25)
        case .photoResistor: return PartDefaults(value: 5_000, secondaryValue: 100)
        case .led: return PartDefaults(value: 2)
        case .zenerDiode: return PartDefaults(secondaryValue: 5.1)
        case .bjtNPN, .bjtPNP: return PartDefaults(secondaryValue: 100)
        case .opAmp: return PartDefaults(secondaryValue: 15)
        case .vcvs: return PartDefaults(value: 2)
        case .vccs: return PartDefaults(value: 0.05)
        case .ammeter: return PartDefaults(value: Self.idealAmmeterR)
        case .voltmeter: return PartDefaults(value: Self.idealVoltmeterR)
        case .galvanometer: return PartDefaults(value: 100, secondaryValue: 1e-3)
        case .ohmmeter: return PartDefaults(value: 1e-3)
        case .wattmeter: return PartDefaults(value: 0.05, secondaryValue: 1e6)
        case .multimeter: return PartDefaults(value: Self.idealVoltmeterR, modeIndex: MeterMode.voltage.rawValue)
        default: return PartDefaults()
        }
    }

    private static let idealAmmeterR = 0.001
    private static let idealVoltmeterR = 1e7
}

extension ComponentKind {
    /// Value shown for the primary parameter field in the inspector.
    public var primaryParameterLabel: String {
        switch self {
        case .resistor, .rheostat, .lamp, .galvanometer: return "Resistance (Ω):"
        case .potentiometer: return "Total Track Resistance (Ω):"
        case .fuse: return "On-State Resistance (Ω):"
        case .thermistor: return "Resistance at 25°C (Ω):"
        case .photoResistor: return "Resistance at 10 lux (Ω):"
        case .ammeter: return "Burden Resistance (Ω):"
        case .voltmeter, .multimeter: return "Input Resistance (Ω):"
        case .wattmeter: return "Current-Coil Resistance (Ω):"
        case .ohmmeter: return "Test Current (A):"
        case .capacitor, .electrolyticCapacitor, .trimmerCapacitor: return "Capacitance (F):"
        case .inductor: return "Inductance (H):"
        case .dcVoltageSource: return "Voltage (V):"
        case .acVoltageSource: return "Peak Amplitude (V):"
        case .clockSource, .functionGenerator: return "Amplitude (V):"
        case .dcCurrentSource: return "Current (A):"
        case .vcvs: return "Voltage Gain (μ):"
        case .vccs: return "Transconductance gm (S):"
        case .zenerDiode: return "Forward Drop Model (V):"
        default: return "Value:"
        }
    }

    public var secondaryParameterLabel: String? {
        switch self {
        case .acVoltageSource, .clockSource, .functionGenerator: return "Frequency (Hz):"
        case .potentiometer, .rheostat: return "Wiper / Setting (0–1):"
        case .fuse: return "Rated Current (A):"
        case .thermistor: return "Temperature (°C):"
        case .photoResistor: return "Illuminance (lux):"
        case .galvanometer: return "Full-Scale Current (A):"
        case .wattmeter: return "Pressure-Coil Resistance (Ω):"
        case .zenerDiode: return "Zener Breakdown (V):"
        case .bjtNPN, .bjtPNP: return "Current Gain (β / hFE):"
        default: return nil
        }
    }
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

/// Waveform selected on the function generator (`CircuitComponent.modeIndex`).
public enum GeneratorWaveform: Int, CaseIterable, Sendable {
    case sine = 0
    case square = 1
    case triangle = 2

    public var label: String {
        switch self {
        case .sine: return "Sine"
        case .square: return "Square"
        case .triangle: return "Triangle"
        }
    }
}

/// Measurement mode selected on the multimeter (`CircuitComponent.modeIndex`).
public enum MeterMode: Int, CaseIterable, Sendable {
    case voltage = 0
    case current = 1
    case resistance = 2

    public var label: String {
        switch self {
        case .voltage: return "V (parallel)"
        case .current: return "A (series)"
        case .resistance: return "Ω (ohmmeter)"
        }
    }
}
