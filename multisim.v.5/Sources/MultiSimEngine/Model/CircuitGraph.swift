import Foundation

/// 2D point structure for canvas positioning and wire vertices.
public struct Point2D: Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)

    public static func + (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Point2D, rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public func distance(to other: Point2D) -> Double {
        hypot(x - other.x, y - other.y)
    }
}

/// The direction a lead leaves a terminal, used to route wires orthogonal to the part body.
public enum PinDirection: Int, Sendable {
    case right = 0
    case up = 1
    case left = 2
    case down = 3

    public var unit: Point2D {
        switch self {
        case .right: return Point2D(x: 1, y: 0)
        case .left: return Point2D(x: -1, y: 0)
        case .up: return Point2D(x: 0, y: -1)
        case .down: return Point2D(x: 0, y: 1)
        }
    }

    public var isHorizontal: Bool { self == .left || self == .right }
    public var isVertical: Bool { !isHorizontal }
}

/// A circuit component on the schematic canvas with its pins, electrical values, and physical orientation.
public final class CircuitComponent: Identifiable, Codable, Equatable {
    public let id: UUID
    public var kind: ComponentKind
    public var designator: String
    public var position: Point2D
    /// Orientation in degrees (0, 90, 180, 270)
    public var rotation: Int
    public var pins: [Pin]

    // Primary & secondary electrical values
    public var value: Double
    public var secondaryValue: Double
    public var stateBool: Bool
    public var ledColor: LEDColor
    /// Multi-position selector for parts with modes (function generator waveform, multimeter range).
    public var modeIndex: Int

    // Real-time runtime simulation variables (not saved to file)
    public var runtimeVoltageDrop: Double = 0.0
    public var runtimeCurrent: Double = 0.0
    public var runtimePrevVoltage: Double = 0.0
    public var runtimePrevCurrent: Double = 0.0
    /// Derived reading for instruments (deflection %, resistance, power...) - not saved.
    public var runtimeReading: Double = 0.0

    enum CodingKeys: String, CodingKey {
        case id, kind, designator, position, rotation, pins, value, secondaryValue, stateBool, ledColor, modeIndex
    }

    public init(
        id: UUID = UUID(),
        kind: ComponentKind,
        designator: String,
        position: Point2D = .zero,
        rotation: Int = 0,
        value: Double = 0.0,
        secondaryValue: Double = 0.0,
        stateBool: Bool = false,
        ledColor: LEDColor = .red,
        modeIndex: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.designator = designator
        self.position = position
        self.rotation = rotation
        self.value = value
        self.secondaryValue = secondaryValue
        self.stateBool = stateBool
        self.ledColor = ledColor
        self.modeIndex = modeIndex
        self.pins = Self.defaultPins(for: kind)
    }

    /// Hand-written so circuit files saved before `modeIndex` existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ComponentKind.self, forKey: .kind)
        designator = try c.decode(String.self, forKey: .designator)
        position = try c.decode(Point2D.self, forKey: .position)
        rotation = try c.decode(Int.self, forKey: .rotation)
        value = try c.decode(Double.self, forKey: .value)
        secondaryValue = try c.decode(Double.self, forKey: .secondaryValue)
        stateBool = try c.decode(Bool.self, forKey: .stateBool)
        ledColor = try c.decode(LEDColor.self, forKey: .ledColor)
        modeIndex = try c.decodeIfPresent(Int.self, forKey: .modeIndex) ?? 0
        pins = try c.decode([Pin].self, forKey: .pins)
    }

    public static func == (lhs: CircuitComponent, rhs: CircuitComponent) -> Bool {
        lhs.id == rhs.id
    }

    /// Rotated offset of a pin from the component centre.
    public func rotatedOffset(pinIndex: Int) -> Point2D {
        guard pinIndex < pins.count else { return .zero }
        let pin = pins[pinIndex]
        let rad = Double(rotation) * .pi / 180.0
        let cosA = cos(rad)
        let sinA = sin(rad)
        let rx = pin.relativeX * cosA - pin.relativeY * sinA
        let ry = pin.relativeX * sinA + pin.relativeY * cosA
        return Point2D(x: rx, y: ry)
    }

    /// Computes the absolute coordinates of a pin on the canvas based on component position & rotation.
    public func absolutePinPosition(pinIndex: Int) -> Point2D {
        position + rotatedOffset(pinIndex: pinIndex)
    }

    /// Absolute pin position when the component were somewhere else - used to evaluate a drag before committing it.
    public func absolutePinPosition(pinIndex: Int, at hypothetical: Point2D) -> Point2D {
        hypothetical + rotatedOffset(pinIndex: pinIndex)
    }

    /// Which way the lead sticks out of this pin, given the current rotation.
    public func pinExitDirection(pinIndex: Int) -> PinDirection {
        guard pinIndex < pins.count else { return .right }
        let off = rotatedOffset(pinIndex: pinIndex)
        if abs(off.x) >= abs(off.y) {
            if off.x >= 0 { return .right }
            return .left
        }
        return off.y >= 0 ? .down : .up
    }

    /// Bounding half-size of the symbol body, used for hit testing and wire clearance.
    public var bodyHalfSize: Double {
        switch kind {
        case .opAmp, .logicAND, .logicOR, .logicNAND, .logicNOR, .logicXOR, .logicXNOR, .logicBuffer,
             .vcvs, .vccs, .wattmeter, .bjtNPN, .bjtPNP:
            return 34
        case .ground, .probe:
            return 22
        default:
            return 30
        }
    }

    /// Generates standard pins with relative offsets (in canvas points) for each component type.
    public static func defaultPins(for kind: ComponentKind) -> [Pin] {
        switch kind {
        case .ground:
            // Single pin at top (0, -20)
            return [Pin(index: 0, name: "GND", relativeX: 0, relativeY: -20)]

        case .probe:
            // Single pin at the bottom; the readout sits above it
            return [Pin(index: 0, name: "PROBE", relativeX: 0, relativeY: 30)]

        case .dcVoltageSource, .acVoltageSource, .clockSource, .functionGenerator:
            // Pin 0 = Positive (top, 0, -30), Pin 1 = Negative (bottom, 0, 30)
            return [
                Pin(index: 0, name: "+", relativeX: 0, relativeY: -30),
                Pin(index: 1, name: "-", relativeX: 0, relativeY: 30)
            ]

        case .dcCurrentSource:
            return [
                Pin(index: 0, name: "OUT", relativeX: 0, relativeY: -30),
                Pin(index: 1, name: "IN", relativeX: 0, relativeY: 30)
            ]

        case .resistor, .capacitor, .electrolyticCapacitor, .trimmerCapacitor, .inductor,
             .switchSPST, .rheostat, .lamp, .fuse, .thermistor, .photoResistor:
            // Standard two-terminal passive (left: -30, 0; right: 30, 0)
            return [
                Pin(index: 0, name: "A", relativeX: -30, relativeY: 0),
                Pin(index: 1, name: "B", relativeX: 30, relativeY: 0)
            ]

        case .potentiometer:
            // Potential divider: track ends A/B on the sides, wiper W on the bottom.
            return [
                Pin(index: 0, name: "A", relativeX: -30, relativeY: 0),
                Pin(index: 1, name: "B", relativeX: 30, relativeY: 0),
                Pin(index: 2, name: "W", relativeX: 0, relativeY: 30)
            ]

        case .ammeter, .voltmeter, .galvanometer, .ohmmeter, .multimeter:
            return [
                Pin(index: 0, name: "IN", relativeX: -30, relativeY: 0),
                Pin(index: 1, name: "OUT", relativeX: 30, relativeY: 0)
            ]

        case .wattmeter:
            // Top pair = current coil (in series), bottom pair = pressure coil (across the load)
            return [
                Pin(index: 0, name: "CC+", relativeX: -30, relativeY: -16),
                Pin(index: 1, name: "CC-", relativeX: 30, relativeY: -16),
                Pin(index: 2, name: "PC+", relativeX: -30, relativeY: 16),
                Pin(index: 3, name: "PC-", relativeX: 30, relativeY: 16)
            ]

        case .diode, .led, .zenerDiode, .schottkyDiode:
            // Pin 0 = Anode (left, -30, 0), Pin 1 = Cathode (right, 30, 0)
            return [
                Pin(index: 0, name: "Anode", relativeX: -30, relativeY: 0),
                Pin(index: 1, name: "Cathode", relativeX: 30, relativeY: 0)
            ]

        case .bjtNPN, .bjtPNP:
            // Pin 0 = Base (left, -30, 0), Pin 1 = Collector (top right, 20, -30), Pin 2 = Emitter (bottom right, 20, 30)
            return [
                Pin(index: 0, name: "Base", relativeX: -30, relativeY: 0),
                Pin(index: 1, name: "Collector", relativeX: 20, relativeY: -30),
                Pin(index: 2, name: "Emitter", relativeX: 20, relativeY: 30)
            ]

        case .vcvs, .vccs:
            // 4-terminal controlled source: Control inputs (left), Controlled outputs (right)
            return [
                Pin(index: 0, name: "OUT+", relativeX: 25, relativeY: -20),
                Pin(index: 1, name: "OUT-", relativeX: 25, relativeY: 20),
                Pin(index: 2, name: "IN+", relativeX: -25, relativeY: -20),
                Pin(index: 3, name: "IN-", relativeX: -25, relativeY: 20)
            ]

        case .opAmp:
            // Pin 0 = Inverting (-), Pin 1 = Non-Inverting (+), Pin 2 = Output
            return [
                Pin(index: 0, name: "-", relativeX: -40, relativeY: -20),
                Pin(index: 1, name: "+", relativeX: -40, relativeY: 20),
                Pin(index: 2, name: "OUT", relativeX: 40, relativeY: 0)
            ]

        case .logicAND, .logicOR, .logicNAND, .logicNOR, .logicXOR, .logicXNOR:
            // 2 inputs on left, 1 output on right
            return [
                Pin(index: 0, name: "IN1", relativeX: -30, relativeY: -15),
                Pin(index: 1, name: "IN2", relativeX: -30, relativeY: 15),
                Pin(index: 2, name: "OUT", relativeX: 30, relativeY: 0)
            ]

        case .logicNOT, .logicBuffer:
            // 1 input on left, 1 output on right
            return [
                Pin(index: 0, name: "IN", relativeX: -30, relativeY: 0),
                Pin(index: 1, name: "OUT", relativeX: 30, relativeY: 0)
            ]
        }
    }
}

/// A wire connection connecting two pins or vertices on the schematic canvas.
public struct Wire: Identifiable, Codable, Equatable {
    public let id: UUID
    public var startPinId: UUID
    public var endPinId: UUID
    /// Manual corner/through points. A single waypoint that lies on another wire marks a T-junction stub.
    public var waypoints: [Point2D]
    /// Instantaneous calculated current through wire (for animation)
    public var runtimeCurrent: Double = 0.0

    enum CodingKeys: String, CodingKey {
        case id, startPinId, endPinId, waypoints
    }

    public init(id: UUID = UUID(), startPinId: UUID, endPinId: UUID, waypoints: [Point2D] = []) {
        self.id = id
        self.startPinId = startPinId
        self.endPinId = endPinId
        self.waypoints = waypoints
    }
}

/// Complete Circuit Model representing the user's schematic document.
public final class Circuit: Codable {
    public var components: [CircuitComponent]
    public var wires: [Wire]

    public init(components: [CircuitComponent] = [], wires: [Wire] = []) {
        self.components = components
        self.wires = wires
    }

    /// Looks up the owner of a pin id.
    public func component(owningPin pinId: UUID) -> (component: CircuitComponent, pin: Pin)? {
        for comp in components {
            if let pin = comp.pins.first(where: { $0.id == pinId }) {
                return (comp, pin)
            }
        }
        return nil
    }

    public func component(id: UUID) -> CircuitComponent? {
        components.first { $0.id == id }
    }

    /// Absolute position of a pin by id, or nil when the pin no longer exists.
    public func pinPosition(_ pinId: UUID) -> Point2D? {
        guard let (comp, pin) = component(owningPin: pinId) else { return nil }
        return comp.absolutePinPosition(pinIndex: pin.index)
    }

    /// Resolves the electrical netlist using Union-Find algorithm.
    /// Maps each Pin ID to an electrical Node Index:
    /// Node 0 is permanently reserved for Ground.
    /// Active circuit nodes are numbered 1, 2, 3, ...
    public func resolveNodes() -> (pinToNode: [UUID: Int], totalNodes: Int) {
        var parent = [UUID: UUID]()

        func find(_ id: UUID) -> UUID {
            if parent[id] == nil {
                parent[id] = id
                return id
            }
            if parent[id] == id {
                return id
            }
            let root = find(parent[id]!)
            parent[id] = root
            return root
        }

        func union(_ a: UUID, _ b: UUID) {
            let rootA = find(a)
            let rootB = find(b)
            if rootA != rootB {
                parent[rootB] = rootA
            }
        }

        // Register all pins
        for comp in components {
            for pin in comp.pins {
                _ = find(pin.id)
            }
        }

        // Union connected pins from wires
        for wire in wires {
            union(wire.startPinId, wire.endPinId)
        }

        // Identify all Ground pins to ensure their root is mapped to Node 0
        var groundRoots = Set<UUID>()
        for comp in components where comp.kind == .ground {
            if let pin = comp.pins.first {
                groundRoots.insert(find(pin.id))
            }
        }

        // Assign node indices (0 for Ground, 1..N for others)
        var rootToNode = [UUID: Int]()
        var nextNodeIndex = 1

        for comp in components {
            for pin in comp.pins {
                let root = find(pin.id)
                if groundRoots.contains(root) {
                    rootToNode[root] = 0
                } else if rootToNode[root] == nil {
                    rootToNode[root] = nextNodeIndex
                    nextNodeIndex += 1
                }
            }
        }

        var pinToNode = [UUID: Int]()
        for comp in components {
            for pin in comp.pins {
                let root = find(pin.id)
                pinToNode[pin.id] = rootToNode[root] ?? 0
            }
        }

        return (pinToNode, nextNodeIndex - 1)
    }
}
