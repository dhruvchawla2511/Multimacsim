import SwiftUI
import MultiSimEngine

/// Renders crisp, vector electronic schematic symbols for any component kind.
public struct ComponentSymbolView: View {
    public let component: CircuitComponent
    public let isSelected: Bool

    public init(component: CircuitComponent, isSelected: Bool) {
        self.component = component
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            symbolContent

            // Special fills/indicators
            if component.kind == .led && component.runtimeCurrent > 1e-4 {
                // Glow effect when LED is conducting
                Circle()
                    .fill(ledColor.opacity(min(component.runtimeCurrent / 0.02, 1.0) * 0.8))
                    .frame(width: 24, height: 24)
                    .blur(radius: 6)
            }
        }
        .frame(width: 60, height: 60)
        .rotationEffect(.degrees(Double(component.rotation)))
    }

    private var symbolColor: Color {
        if isSelected {
            return .accentColor
        }
        return .primary
    }

    private var lineWidth: CGFloat {
        isSelected ? 2.5 : 1.8
    }

    private var ledColor: Color {
        switch component.ledColor {
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .yellow: return .yellow
        case .white: return .white
        }
    }

    @ViewBuilder
    private var symbolContent: some View {
        switch component.kind {
        case .resistor:
            ResistorSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .capacitor:
            CapacitorSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .inductor:
            InductorSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .dcVoltageSource:
            DCSourceSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .acVoltageSource:
            ACSourceSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .clockSource:
            ClockSourceSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .dcCurrentSource:
            CurrentSourceSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .ground:
            GroundSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .diode:
            DiodeSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .led:
            LEDSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .zenerDiode:
            ZenerSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .switchSPST:
            SwitchSymbol(isOpen: !component.stateBool).stroke(symbolColor, lineWidth: lineWidth)
        case .potentiometer:
            PotentiometerSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .bjtNPN:
            BJTSymbol(isNPN: true).stroke(symbolColor, lineWidth: lineWidth)
        case .bjtPNP:
            BJTSymbol(isNPN: false).stroke(symbolColor, lineWidth: lineWidth)
        case .opAmp:
            OpAmpSymbol().stroke(symbolColor, lineWidth: lineWidth)
        case .vcvs:
            DependentSourceSymbol(isVoltageSource: true).stroke(symbolColor, lineWidth: lineWidth)
        case .vccs:
            DependentSourceSymbol(isVoltageSource: false).stroke(symbolColor, lineWidth: lineWidth)
        case .logicAND:
            LogicGateSymbol(gateType: .and).stroke(symbolColor, lineWidth: lineWidth)
        case .logicOR:
            LogicGateSymbol(gateType: .or).stroke(symbolColor, lineWidth: lineWidth)
        case .logicNOT:
            LogicGateSymbol(gateType: .not).stroke(symbolColor, lineWidth: lineWidth)
        case .logicNAND:
            LogicGateSymbol(gateType: .nand).stroke(symbolColor, lineWidth: lineWidth)
        case .logicNOR:
            LogicGateSymbol(gateType: .nor).stroke(symbolColor, lineWidth: lineWidth)
        case .logicXOR:
            LogicGateSymbol(gateType: .xor).stroke(symbolColor, lineWidth: lineWidth)
        }
    }
}

// MARK: - Individual Component Geometric Shapes

public struct ResistorSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: 12, y: midY))
        // Zigzag (3 peaks, 3 valleys)
        path.addLine(to: CGPoint(x: 16, y: midY - 10))
        path.addLine(to: CGPoint(x: 24, y: midY + 10))
        path.addLine(to: CGPoint(x: 32, y: midY - 10))
        path.addLine(to: CGPoint(x: 40, y: midY + 10))
        path.addLine(to: CGPoint(x: 44, y: midY - 10))
        path.addLine(to: CGPoint(x: 48, y: midY))
        path.addLine(to: CGPoint(x: 60, y: midY))
        return path
    }
}

public struct CapacitorSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        // Lead 1
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: 26, y: midY))
        // Plate 1
        path.move(to: CGPoint(x: 26, y: midY - 14))
        path.addLine(to: CGPoint(x: 26, y: midY + 14))
        // Plate 2
        path.move(to: CGPoint(x: 34, y: midY - 14))
        path.addLine(to: CGPoint(x: 34, y: midY + 14))
        // Lead 2
        path.move(to: CGPoint(x: 34, y: midY))
        path.addLine(to: CGPoint(x: 60, y: midY))
        return path
    }
}

public struct InductorSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: 12, y: midY))
        // 4 Coils (arcs)
        for i in 0..<4 {
            let startX = 12.0 + Double(i) * 9.0
            let endX = startX + 9.0
            path.addArc(
                center: CGPoint(x: (startX + endX) / 2.0, y: midY),
                radius: 4.5,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: 60, y: midY))
        return path
    }
}

public struct DCSourceSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        // Leads
        path.move(to: CGPoint(x: midX, y: 0))
        path.addLine(to: CGPoint(x: midX, y: 14))
        path.move(to: CGPoint(x: midX, y: 46))
        path.addLine(to: CGPoint(x: midX, y: 60))
        // Circle
        path.addEllipse(in: CGRect(x: midX - 16, y: 14, width: 32, height: 32))
        // Plus (+) sign at top
        path.move(to: CGPoint(x: midX, y: 20))
        path.addLine(to: CGPoint(x: midX, y: 26))
        path.move(to: CGPoint(x: midX - 3, y: 23))
        path.addLine(to: CGPoint(x: midX + 3, y: 23))
        // Minus (-) sign at bottom
        path.move(to: CGPoint(x: midX - 3, y: 37))
        path.addLine(to: CGPoint(x: midX + 3, y: 37))
        return path
    }
}

public struct ACSourceSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY
        // Leads
        path.move(to: CGPoint(x: midX, y: 0))
        path.addLine(to: CGPoint(x: midX, y: 14))
        path.move(to: CGPoint(x: midX, y: 46))
        path.addLine(to: CGPoint(x: midX, y: 60))
        // Circle
        path.addEllipse(in: CGRect(x: midX - 16, y: 14, width: 32, height: 32))
        // Sine wave (~)
        path.move(to: CGPoint(x: midX - 8, y: midY))
        path.addQuadCurve(to: CGPoint(x: midX, y: midY), control: CGPoint(x: midX - 4, y: midY - 6))
        path.addQuadCurve(to: CGPoint(x: midX + 8, y: midY), control: CGPoint(x: midX + 4, y: midY + 6))
        return path
    }
}

public struct ClockSourceSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY
        path.move(to: CGPoint(x: midX, y: 0))
        path.addLine(to: CGPoint(x: midX, y: 14))
        path.move(to: CGPoint(x: midX, y: 46))
        path.addLine(to: CGPoint(x: midX, y: 60))
        path.addEllipse(in: CGRect(x: midX - 16, y: 14, width: 32, height: 32))
        // Square pulse
        path.move(to: CGPoint(x: midX - 8, y: midY + 4))
        path.addLine(to: CGPoint(x: midX - 8, y: midY - 4))
        path.addLine(to: CGPoint(x: midX, y: midY - 4))
        path.addLine(to: CGPoint(x: midX, y: midY + 4))
        path.addLine(to: CGPoint(x: midX + 8, y: midY + 4))
        return path
    }
}

public struct CurrentSourceSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        path.move(to: CGPoint(x: midX, y: 0))
        path.addLine(to: CGPoint(x: midX, y: 14))
        path.move(to: CGPoint(x: midX, y: 46))
        path.addLine(to: CGPoint(x: midX, y: 60))
        path.addEllipse(in: CGRect(x: midX - 16, y: 14, width: 32, height: 32))
        // Upward arrow
        path.move(to: CGPoint(x: midX, y: 40))
        path.addLine(to: CGPoint(x: midX, y: 20))
        path.addLine(to: CGPoint(x: midX - 4, y: 26))
        path.move(to: CGPoint(x: midX, y: 20))
        path.addLine(to: CGPoint(x: midX + 4, y: 26))
        return path
    }
}

public struct GroundSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        // Vertical stem
        path.move(to: CGPoint(x: midX, y: 10))
        path.addLine(to: CGPoint(x: midX, y: 30))
        // 3 Descending bars
        path.move(to: CGPoint(x: midX - 16, y: 30))
        path.addLine(to: CGPoint(x: midX + 16, y: 30))
        path.move(to: CGPoint(x: midX - 10, y: 36))
        path.addLine(to: CGPoint(x: midX + 10, y: 36))
        path.move(to: CGPoint(x: midX - 4, y: 42))
        path.addLine(to: CGPoint(x: midX + 4, y: 42))
        return path
    }
}

public struct DiodeSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: 22, y: midY))
        // Triangle (pointing right)
        path.move(to: CGPoint(x: 22, y: midY - 12))
        path.addLine(to: CGPoint(x: 22, y: midY + 12))
        path.addLine(to: CGPoint(x: 38, y: midY))
        path.closeSubpath()
        // Cathode bar
        path.move(to: CGPoint(x: 38, y: midY - 12))
        path.addLine(to: CGPoint(x: 38, y: midY + 12))
        // Cathode lead
        path.move(to: CGPoint(x: 38, y: midY))
        path.addLine(to: CGPoint(x: 60, y: midY))
        return path
    }
}

public struct LEDSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = DiodeSymbol().path(in: rect)
        let midY = rect.midY
        // Two outgoing emission arrows
        path.move(to: CGPoint(x: 34, y: midY - 10))
        path.addLine(to: CGPoint(x: 44, y: midY - 20))
        path.addLine(to: CGPoint(x: 40, y: midY - 20))
        path.move(to: CGPoint(x: 44, y: midY - 20))
        path.addLine(to: CGPoint(x: 44, y: midY - 16))

        path.move(to: CGPoint(x: 40, y: midY - 6))
        path.addLine(to: CGPoint(x: 50, y: midY - 16))
        path.addLine(to: CGPoint(x: 46, y: midY - 16))
        path.move(to: CGPoint(x: 50, y: midY - 16))
        path.addLine(to: CGPoint(x: 50, y: midY - 12))
        return path
    }
}

public struct ZenerSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = DiodeSymbol().path(in: rect)
        let midY = rect.midY
        // Zener cathode wings
        path.move(to: CGPoint(x: 38, y: midY - 12))
        path.addLine(to: CGPoint(x: 34, y: midY - 16))
        path.move(to: CGPoint(x: 38, y: midY + 12))
        path.addLine(to: CGPoint(x: 42, y: midY + 16))
        return path
    }
}

public struct SwitchSymbol: Shape {
    public let isOpen: Bool

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        // Terminal circles
        path.addEllipse(in: CGRect(x: 16, y: midY - 3, width: 6, height: 6))
        path.addEllipse(in: CGRect(x: 38, y: midY - 3, width: 6, height: 6))
        // Leads
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: 16, y: midY))
        path.move(to: CGPoint(x: 44, y: midY))
        path.addLine(to: CGPoint(x: 60, y: midY))
        // Lever
        path.move(to: CGPoint(x: 22, y: midY))
        if isOpen {
            path.addLine(to: CGPoint(x: 38, y: midY - 14))
        } else {
            path.addLine(to: CGPoint(x: 38, y: midY))
        }
        return path
    }
}

public struct PotentiometerSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = ResistorSymbol().path(in: rect)
        let midX = rect.midX
        let midY = rect.midY
        // Draggable wiper arrow
        path.move(to: CGPoint(x: midX - 10, y: midY + 20))
        path.addLine(to: CGPoint(x: midX + 6, y: midY + 4))
        path.addLine(to: CGPoint(x: midX, y: midY + 4))
        path.move(to: CGPoint(x: midX + 6, y: midY + 4))
        path.addLine(to: CGPoint(x: midX + 6, y: midY + 10))
        return path
    }
}

public struct BJTSymbol: Shape {
    public let isNPN: Bool

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY
        // Outer circle
        path.addEllipse(in: CGRect(x: midX - 20, y: midY - 20, width: 40, height: 40))
        // Base bar
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: midX - 6, y: midY))
        path.move(to: CGPoint(x: midX - 6, y: midY - 14))
        path.addLine(to: CGPoint(x: midX - 6, y: midY + 14))
        // Collector lead
        path.move(to: CGPoint(x: midX - 6, y: midY - 8))
        path.addLine(to: CGPoint(x: midX + 12, y: midY - 18))
        path.addLine(to: CGPoint(x: midX + 12, y: 0))
        // Emitter lead
        path.move(to: CGPoint(x: midX - 6, y: midY + 8))
        path.addLine(to: CGPoint(x: midX + 12, y: midY + 18))
        path.addLine(to: CGPoint(x: midX + 12, y: 60))
        // Emitter arrow
        if isNPN {
            path.move(to: CGPoint(x: midX + 10, y: midY + 17))
            path.addLine(to: CGPoint(x: midX + 2, y: midY + 16))
            path.move(to: CGPoint(x: midX + 10, y: midY + 17))
            path.addLine(to: CGPoint(x: midX + 8, y: midY + 10))
        } else {
            path.move(to: CGPoint(x: midX, y: midY + 11))
            path.addLine(to: CGPoint(x: midX + 6, y: midY + 14))
            path.move(to: CGPoint(x: midX, y: midY + 11))
            path.addLine(to: CGPoint(x: midX + 2, y: midY + 17))
        }
        return path
    }
}

public struct OpAmpSymbol: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        // Triangle
        path.move(to: CGPoint(x: 10, y: 6))
        path.addLine(to: CGPoint(x: 10, y: 54))
        path.addLine(to: CGPoint(x: 52, y: 30))
        path.closeSubpath()
        // Output lead
        path.move(to: CGPoint(x: 52, y: 30))
        path.addLine(to: CGPoint(x: 60, y: 30))
        // Inverting (-) sign
        path.move(to: CGPoint(x: 15, y: 18))
        path.addLine(to: CGPoint(x: 21, y: 18))
        // Non-inverting (+) sign
        path.move(to: CGPoint(x: 15, y: 42))
        path.addLine(to: CGPoint(x: 21, y: 42))
        path.move(to: CGPoint(x: 18, y: 39))
        path.addLine(to: CGPoint(x: 18, y: 45))
        return path
    }
}

public enum LogicGateType: Sendable {
    case and, or, not, nand, nor, xor
}

public struct LogicGateSymbol: Shape {
    public let gateType: LogicGateType

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        switch gateType {
        case .and, .nand:
            path.move(to: CGPoint(x: 12, y: 12))
            path.addLine(to: CGPoint(x: 32, y: 12))
            path.addArc(center: CGPoint(x: 32, y: midY), radius: 18, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: 12, y: 48))
            path.closeSubpath()
            if gateType == .nand {
                path.addEllipse(in: CGRect(x: 50, y: midY - 3, width: 6, height: 6))
            }
        case .or, .nor:
            path.move(to: CGPoint(x: 12, y: 12))
            path.addQuadCurve(to: CGPoint(x: 50, y: midY), control: CGPoint(x: 36, y: 16))
            path.addQuadCurve(to: CGPoint(x: 12, y: 48), control: CGPoint(x: 36, y: 44))
            path.addQuadCurve(to: CGPoint(x: 12, y: 12), control: CGPoint(x: 22, y: midY))
            if gateType == .nor {
                path.addEllipse(in: CGRect(x: 50, y: midY - 3, width: 6, height: 6))
            }
        case .not:
            path.move(to: CGPoint(x: 14, y: 14))
            path.addLine(to: CGPoint(x: 44, y: midY))
            path.addLine(to: CGPoint(x: 14, y: 46))
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: 44, y: midY - 3, width: 6, height: 6))
        case .xor:
            path.move(to: CGPoint(x: 16, y: 12))
            path.addQuadCurve(to: CGPoint(x: 50, y: midY), control: CGPoint(x: 36, y: 16))
            path.addQuadCurve(to: CGPoint(x: 16, y: 48), control: CGPoint(x: 36, y: 44))
            path.addQuadCurve(to: CGPoint(x: 16, y: 12), control: CGPoint(x: 24, y: midY))
            // Extra input arc
            path.move(to: CGPoint(x: 10, y: 12))
            path.addQuadCurve(to: CGPoint(x: 10, y: 48), control: CGPoint(x: 18, y: midY))
        }
        return path
    }
}

public struct DependentSourceSymbol: Shape {
    public let isVoltageSource: Bool

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX + 5
        let midY = rect.midY

        // Controlled Output Diamond
        path.move(to: CGPoint(x: midX, y: midY - 18))
        path.addLine(to: CGPoint(x: midX + 18, y: midY))
        path.addLine(to: CGPoint(x: midX, y: midY + 18))
        path.addLine(to: CGPoint(x: midX - 18, y: midY))
        path.closeSubpath()

        // Output leads
        path.move(to: CGPoint(x: midX, y: midY - 18))
        path.addLine(to: CGPoint(x: midX, y: 0))
        path.move(to: CGPoint(x: midX, y: midY + 18))
        path.addLine(to: CGPoint(x: midX, y: 60))

        // Control leads (left)
        path.move(to: CGPoint(x: 0, y: midY - 10))
        path.addLine(to: CGPoint(x: midX - 18, y: midY - 10))
        path.move(to: CGPoint(x: 0, y: midY + 10))
        path.addLine(to: CGPoint(x: midX - 18, y: midY + 10))

        if isVoltageSource {
            // Plus (+) sign near top
            path.move(to: CGPoint(x: midX, y: midY - 10))
            path.addLine(to: CGPoint(x: midX, y: midY - 4))
            path.move(to: CGPoint(x: midX - 3, y: midY - 7))
            path.addLine(to: CGPoint(x: midX + 3, y: midY - 7))
            // Minus (-) sign near bottom
            path.move(to: CGPoint(x: midX - 3, y: midY + 7))
            path.addLine(to: CGPoint(x: midX + 3, y: midY + 7))
        } else {
            // Arrow pointing up
            path.move(to: CGPoint(x: midX, y: midY + 8))
            path.addLine(to: CGPoint(x: midX, y: midY - 8))
            path.addLine(to: CGPoint(x: midX - 3, y: midY - 3))
            path.move(to: CGPoint(x: midX, y: midY - 8))
            path.addLine(to: CGPoint(x: midX + 3, y: midY - 3))
        }

        return path
    }
}
