import SwiftUI
import MultiSimEngine

/// The upgraded interactive 2D schematic canvas featuring seamless component dragging,
/// effortless magnetic pin wiring, live on-canvas node voltage badges, and canvas panning.
public struct SchematicCanvasView: View {
    @ObservedObject var viewModel: CircuitEditorViewModel

    @State private var dragStartPositions: [UUID: Point2D] = [:]
    @State private var panStartOffset: CGPoint? = nil
    @State private var hoveredPinId: UUID? = nil

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Main Interactive Canvas Area
                ZStack {
                    // 1. Grid, Wires, and Electron Animations
                    Canvas { context, size in
                        drawGrid(context: context, size: size)
                        drawWires(context: context)
                        drawCurrentAnimation(context: context)
                        drawJunctionDots(context: context)
                    }
                    .drawingGroup()

                    // 2. Active Wire Drafting Rubber-Band Preview
                    if let draft = viewModel.wireDraftStartPin,
                       let currentPoint = viewModel.wireDraftCurrentPoint,
                       let startComp = viewModel.circuit.components.first(where: { $0.id == draft.componentId }) {
                        let startPoint = startComp.absolutePinPosition(pinIndex: draft.pin.index)
                        Path { path in
                            path.move(to: CGPoint(x: startPoint.x, y: startPoint.y))
                            path.addLine(to: CGPoint(x: currentPoint.x, y: startPoint.y))
                            path.addLine(to: currentPoint)
                        }
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                    }

                    // 3. Components Layer (Symbols, Labels & Smooth Dragging)
                    ForEach(viewModel.circuit.components) { comp in
                        componentView(for: comp)
                    }

                    // 4. Pin Terminals Layer (Rendered in Canvas Space at Terminal Leads)
                    ForEach(viewModel.circuit.components) { comp in
                        ForEach(comp.pins) { pin in
                            pinTerminalView(component: comp, pin: pin)
                        }
                    }

                    // 5. Live On-Canvas Node Voltage Badges
                    if viewModel.showNodeVoltages && viewModel.isSimulating {
                        ForEach(viewModel.circuit.components) { comp in
                            ForEach(comp.pins) { pin in
                                let pos = comp.absolutePinPosition(pinIndex: pin.index)
                                let nodeIdx = viewModel.solver.pinToNode[pin.id] ?? 0
                                let v = viewModel.latestNodeVoltages[nodeIdx] ?? 0.0

                                Text(nodeIdx == 0 ? "0V" : String(format: "%.1fV", v))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(nodeIdx == 0 ? Color.secondary : (v >= 0 ? Color.green : Color.cyan))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                    .offset(y: -15)
                                    .position(x: pos.x, y: pos.y)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Color(nsColor: .windowBackgroundColor)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    // Pan canvas when dragging empty background (and not wiring)
                                    if viewModel.wireDraftStartPin == nil {
                                        if panStartOffset == nil {
                                            panStartOffset = viewModel.panOffset
                                        }
                                        if let start = panStartOffset {
                                            viewModel.panOffset = CGPoint(
                                                x: start.x + value.translation.width,
                                                y: start.y + value.translation.height
                                            )
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    panStartOffset = nil
                                }
                        )
                        .onTapGesture {
                            if viewModel.wireDraftStartPin != nil {
                                viewModel.cancelWiring()
                            } else {
                                viewModel.selectedComponentId = nil
                                viewModel.selectedWireId = nil
                            }
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if viewModel.wireDraftStartPin != nil {
                            viewModel.wireDraftCurrentPoint = location
                        }
                    case .ended:
                        break
                    }
                }
                .scaleEffect(viewModel.zoomScale)
                .offset(x: viewModel.panOffset.x, y: viewModel.panOffset.y)

                // Top Floating Status HUD Banner
                if let status = viewModel.lastConnectedWireDescription {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.wireDraftStartPin != nil ? "bolt.fill" : "checkmark.circle.fill")
                            .foregroundStyle(viewModel.wireDraftStartPin != nil ? .orange : .green)
                        Text(status)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)

                        if viewModel.wireDraftStartPin != nil {
                            Button("Cancel (Esc)") {
                                viewModel.cancelWiring()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 3)
                    .padding(.top, 10)
                }
            }
        }
    }

    // MARK: - Component Rendering (Symbols, Selection & Smooth Dragging)

    private func componentView(for comp: CircuitComponent) -> some View {
        let isSelected = viewModel.selectedComponentId == comp.id

        return ZStack {
            // Selection bounding highlight
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 68, height: 68)
            }

            // Symbol
            ComponentSymbolView(component: comp, isSelected: isSelected)

            // Labels: Designator & Value
            VStack(spacing: 2) {
                Text(comp.designator)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                Text(formattedValue(for: comp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .offset(y: labelOffsetY(for: comp))
        }
        .frame(width: 60, height: 60)
        .contentShape(Rectangle())
        .position(x: comp.position.x, y: comp.position.y)
        .onTapGesture {
            if comp.kind == .switchSPST {
                viewModel.toggleSwitch(componentId: comp.id)
            } else {
                viewModel.selectedComponentId = comp.id
                viewModel.selectedWireId = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if dragStartPositions[comp.id] == nil {
                        dragStartPositions[comp.id] = comp.position
                        viewModel.selectedComponentId = comp.id
                        viewModel.selectedWireId = nil
                    }
                    guard let startPos = dragStartPositions[comp.id] else { return }
                    let targetX = startPos.x + value.translation.width
                    let targetY = startPos.y + value.translation.height
                    let snappedX = round(targetX / viewModel.gridSize) * viewModel.gridSize
                    let snappedY = round(targetY / viewModel.gridSize) * viewModel.gridSize
                    viewModel.updateComponentPosition(id: comp.id, newPosition: Point2D(x: snappedX, y: snappedY))
                }
                .onEnded { _ in
                    dragStartPositions[comp.id] = nil
                    viewModel.solver.rebuildNetlist()
                    viewModel.objectWillChange.send()
                }
        )
    }

    // MARK: - Magnetic Pin Terminals (Canvas Space)

    private func pinTerminalView(component: CircuitComponent, pin: Pin) -> some View {
        let pos = component.absolutePinPosition(pinIndex: pin.index)
        let isDraftSource = viewModel.wireDraftStartPin?.pin.id == pin.id
        let isHovered = hoveredPinId == pin.id

        return ZStack {
            // Focused 16x16 hitbox so it stays right at the lead tip without blocking component body
            Color.clear
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())

            // Glowing target ring on hover or drafting
            if isDraftSource || isHovered || viewModel.isWireMode {
                Circle()
                    .stroke(isDraftSource ? Color.green : Color.accentColor, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .scaleEffect(isDraftSource ? 1.25 : 1.0)
            }

            // Visible terminal dot
            Circle()
                .fill(isDraftSource ? Color.green : (isHovered ? Color.green : Color.accentColor))
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
        }
        .position(x: pos.x, y: pos.y)
        .onHover { inside in
            hoveredPinId = inside ? pin.id : nil
            if inside && viewModel.wireDraftStartPin != nil {
                // Magnetically snap wire draft to this pin's exact center
                viewModel.wireDraftCurrentPoint = CGPoint(x: pos.x, y: pos.y)
            }
        }
        .onTapGesture {
            viewModel.handlePinClicked(componentId: component.id, pin: pin)
        }
    }

    // MARK: - Canvas Drawing (Wires, Grid, Electrons)

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let step = viewModel.gridSize
        var dotPath = Path()
        let cols = Int(size.width / step) + 2
        let rows = Int(size.height / step) + 2

        for c in 0..<cols {
            for r in 0..<rows {
                let x = CGFloat(c) * step
                let y = CGFloat(r) * step
                dotPath.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
            }
        }
        context.fill(dotPath, with: .color(Color.secondary.opacity(0.18)))
    }

    private func drawWires(context: GraphicsContext) {
        for wire in viewModel.circuit.wires {
            guard let p1 = resolvePinCoordinate(wire.startPinId),
                  let p2 = resolvePinCoordinate(wire.endPinId) else { continue }

            var path = Path()
            path.move(to: p1)
            let midX = (p1.x + p2.x) / 2.0
            path.addLine(to: CGPoint(x: midX, y: p1.y))
            path.addLine(to: CGPoint(x: midX, y: p2.y))
            path.addLine(to: p2)

            let isSelected = viewModel.selectedWireId == wire.id
            let strokeColor = isSelected ? Color.accentColor : wireColor(for: wire)
            context.stroke(path, with: .color(strokeColor), lineWidth: isSelected ? 3.0 : 2.0)
        }
    }

    private func drawCurrentAnimation(context: GraphicsContext) {
        guard viewModel.isSimulating else { return }

        for wire in viewModel.circuit.wires {
            guard abs(wire.runtimeCurrent) > 1e-6,
                  let p1 = resolvePinCoordinate(wire.startPinId),
                  let p2 = resolvePinCoordinate(wire.endPinId) else { continue }

            let midX = (p1.x + p2.x) / 2.0
            let segments: [(start: CGPoint, end: CGPoint)] = [
                (p1, CGPoint(x: midX, y: p1.y)),
                (CGPoint(x: midX, y: p1.y), CGPoint(x: midX, y: p2.y)),
                (CGPoint(x: midX, y: p2.y), p2)
            ]

            let dotSpacing: CGFloat = 20.0
            let phase = CGFloat(viewModel.animationPhase.truncatingRemainder(dividingBy: Double(dotSpacing)))
            let dir: CGFloat = wire.runtimeCurrent >= 0 ? 1.0 : -1.0

            for seg in segments {
                let dx = seg.end.x - seg.start.x
                let dy = seg.end.y - seg.start.y
                let len = sqrt(dx * dx + dy * dy)
                if len < 2 { continue }

                var dist = (phase * dir).truncatingRemainder(dividingBy: dotSpacing)
                if dist < 0 { dist += dotSpacing }

                while dist < len {
                    let t = dist / len
                    let dotX = seg.start.x + t * dx
                    let dotY = seg.start.y + t * dy

                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: dotX - 2.5, y: dotY - 2.5, width: 5, height: 5))
                    context.fill(dot, with: .color(.yellow.opacity(0.85)))

                    dist += dotSpacing
                }
            }
        }
    }

    private func drawJunctionDots(context: GraphicsContext) {
        var pinCounts = [UUID: Int]()
        for wire in viewModel.circuit.wires {
            pinCounts[wire.startPinId, default: 0] += 1
            pinCounts[wire.endPinId, default: 0] += 1
        }

        for (pinId, count) in pinCounts where count >= 2 {
            if let pt = resolvePinCoordinate(pinId) {
                var dot = Path()
                dot.addEllipse(in: CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(.primary))
            }
        }
    }

    // MARK: - Helpers

    private func resolvePinCoordinate(_ pinId: UUID) -> CGPoint? {
        for comp in viewModel.circuit.components {
            if let idx = comp.pins.firstIndex(where: { $0.id == pinId }) {
                let p2d = comp.absolutePinPosition(pinIndex: idx)
                return CGPoint(x: p2d.x, y: p2d.y)
            }
        }
        return nil
    }

    private func wireColor(for wire: Wire) -> Color {
        if abs(wire.runtimeCurrent) > 1e-4 {
            return Color.green
        }
        return Color.primary.opacity(0.7)
    }

    private func labelOffsetY(for comp: CircuitComponent) -> CGFloat {
        switch comp.kind {
        case .ground: return 32
        case .resistor, .capacitor, .inductor: return 24
        default: return 32
        }
    }

    private func formattedValue(for comp: CircuitComponent) -> String {
        switch comp.kind {
        case .resistor:
            return formatUnits(comp.value, unit: "Ω")
        case .capacitor:
            return formatUnits(comp.value, unit: "F")
        case .inductor:
            return formatUnits(comp.value, unit: "H")
        case .dcVoltageSource:
            return "\(comp.value)V"
        case .acVoltageSource:
            return "\(comp.value)V @ \(Int(comp.secondaryValue > 0 ? comp.secondaryValue : 60))Hz"
        case .clockSource:
            return "\(comp.value)V @ \(Int(comp.secondaryValue > 0 ? comp.secondaryValue : 1000))Hz"
        case .switchSPST:
            return comp.stateBool ? "CLOSED" : "OPEN"
        case .led:
            return comp.ledColor.rawValue.capitalized
        case .zenerDiode:
            return "\(comp.secondaryValue > 0 ? comp.secondaryValue : 5.1)V Zener"
        case .vcvs:
            return "Gain: \(comp.value)x"
        case .vccs:
            return "gm: \(comp.value) S"
        default:
            return ""
        }
    }

    private func formatUnits(_ val: Double, unit: String) -> String {
        if val >= 1e6 { return String(format: "%.1f M%@", val / 1e6, unit) }
        if val >= 1e3 { return String(format: "%.1f k%@", val / 1e3, unit) }
        if val >= 1.0 { return String(format: "%.1f %@", val, unit) }
        if val >= 1e-3 { return String(format: "%.1f m%@", val * 1e3, unit) }
        if val >= 1e-6 { return String(format: "%.1f µ%@", val * 1e6, unit) }
        if val >= 1e-9 { return String(format: "%.1f n%@", val * 1e9, unit) }
        if val >= 1e-12 { return String(format: "%.1f p%@", val * 1e12, unit) }
        return "\(val) \(unit)"
    }
}
