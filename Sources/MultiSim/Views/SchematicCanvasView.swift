import SwiftUI
import MultiSimEngine

/// Interactive schematic canvas.
///
/// All mouse handling lives in ONE gesture on the canvas container. On mouse-down it decides what is
/// under the pointer (a terminal pin, a component body, a wire, or empty space) and then drags, wires
/// or pans accordingly. The drawn layers never receive clicks themselves, so nothing can steal a drag.
public struct SchematicCanvasView: View {
    @ObservedObject var viewModel: CircuitEditorViewModel

    private enum DragMode {
        case idle
        case inert
        case panning(startOffset: CGPoint)
        case moving(id: UUID)
        case wiring
        case wiringClick
    }

    @State private var dragMode: DragMode = .idle
    @State private var hoveredPinId: UUID? = nil

    private let pinHitRadius: CGFloat = 16
    private let bodyHalfSize: CGFloat = 32
    private let clickSlop: CGFloat = 4

    public var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                worldLayer
                    .offset(x: viewModel.panOffset.x, y: viewModel.panOffset.y)
                    .allowsHitTesting(false)

                emptyHint
                statusBanner
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
            .gesture(canvasGesture)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let world = toWorld(location)
                    hoveredPinId = pinHit(at: world)?.pin.id
                    if viewModel.wireDraftStartPin != nil {
                        viewModel.wireDraftCurrentPoint = snapPoint(world)
                    }
                case .ended:
                    hoveredPinId = nil
                }
            }
            .dropDestination(for: String.self) { items, location in
                guard let raw = items.first, let kind = ComponentKind(rawValue: raw) else { return false }
                viewModel.addComponent(kind: kind, at: toWorld(location))
                return true
            }
            .clipped()
        }
    }

    // MARK: - Layers

    private var worldLayer: some View {
        ZStack {
            Canvas { context, size in
                drawGrid(context: context, size: size)
                drawWires(context: context)
                drawCurrentAnimation(context: context)
                drawJunctionDots(context: context)
            }
            .drawingGroup()

            // Rubber-band preview while drawing a wire
            if let draft = viewModel.wireDraftStartPin,
               let currentPoint = viewModel.wireDraftCurrentPoint,
               let startComp = viewModel.circuit.components.first(where: { $0.id == draft.componentId }) {
                let sp = startComp.absolutePinPosition(pinIndex: draft.pin.index)
                let startPoint = CGPoint(x: sp.x, y: sp.y)
                let midX = (startPoint.x + currentPoint.x) / 2.0
                Path { path in
                    path.move(to: startPoint)
                    path.addLine(to: CGPoint(x: midX, y: startPoint.y))
                    path.addLine(to: CGPoint(x: midX, y: currentPoint.y))
                    path.addLine(to: currentPoint)
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
            }

            ForEach(viewModel.circuit.components) { comp in
                componentView(for: comp)
            }

            ForEach(viewModel.circuit.components) { comp in
                ForEach(comp.pins) { pin in
                    pinTerminalView(component: comp, pin: pin)
                }
            }

            if viewModel.showNodeVoltages && viewModel.isSimulating {
                ForEach(viewModel.circuit.components) { comp in
                    ForEach(comp.pins) { pin in
                        voltageBadge(component: comp, pin: pin)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyHint: some View {
        if viewModel.circuit.components.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 34))
                Text("Blank circuit")
                    .font(.headline)
                Text("Drag a part from the left onto the canvas, or click a part to add it.\nDrag from one terminal dot to another to connect them.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
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
                    .keyboardShortcut(.escape, modifiers: [])
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

    private func voltageBadge(component comp: CircuitComponent, pin: Pin) -> some View {
        let pos = comp.absolutePinPosition(pinIndex: pin.index)
        let nodeIdx = viewModel.solver.pinToNode[pin.id] ?? 0
        let v = viewModel.latestNodeVoltages[nodeIdx] ?? 0.0
        let label = nodeIdx == 0 ? "0V" : String(format: "%.1fV", v)
        let color: Color = nodeIdx == 0 ? Color.secondary : (v >= 0 ? Color.green : Color.cyan)

        return Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .offset(y: -15)
            .position(x: pos.x, y: pos.y)
    }

    // MARK: - The one gesture

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value)
            }
    }

    private func toWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - viewModel.panOffset.x, y: p.y - viewModel.panOffset.y)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if case .idle = dragMode {
            beginDrag(atWorld: toWorld(value.startLocation))
        }

        let nowWorld = toWorld(value.location)
        let dist = hypot(value.translation.width, value.translation.height)

        switch dragMode {
        case .idle, .inert:
            break

        case .panning(let startOffset):
            if dist > clickSlop {
                viewModel.panOffset = CGPoint(
                    x: startOffset.x + value.translation.width,
                    y: startOffset.y + value.translation.height
                )
            }

        case .moving(let id):
            if dist > clickSlop,
               let comp = viewModel.circuit.components.first(where: { $0.id == id }) {
                // Move by the screen-space delta from where the part was picked up.
                let grabOrigin = viewModel.dragOrigin(for: id) ?? comp.position
                let targetX = grabOrigin.x + Double(value.translation.width)
                let targetY = grabOrigin.y + Double(value.translation.height)
                let g = Double(viewModel.gridSize)
                let snappedX = (targetX / g).rounded() * g
                let snappedY = (targetY / g).rounded() * g
                viewModel.updateComponentPosition(id: id, newPosition: Point2D(x: snappedX, y: snappedY))
            }

        case .wiring, .wiringClick:
            hoveredPinId = pinHit(at: nowWorld)?.pin.id
            viewModel.wireDraftCurrentPoint = snapPoint(nowWorld)
        }
    }

    private func beginDrag(atWorld world: CGPoint) {
        // A wire is already being drawn (click-click style): this press finishes or cancels it.
        if viewModel.wireDraftStartPin != nil {
            dragMode = .wiringClick
            return
        }

        // Pressing on a terminal dot starts a wire. Drag to another dot and let go, or just click both dots.
        if let hit = pinHit(at: world) {
            viewModel.handlePinClicked(componentId: hit.comp.id, pin: hit.pin)
            dragMode = .wiring
            return
        }

        if let comp = componentHit(at: world) {
            viewModel.selectedComponentId = comp.id
            viewModel.selectedWireId = nil
            if viewModel.isWireMode {
                // In Wire mode parts stay put so a slip never moves them.
                dragMode = .inert
            } else {
                viewModel.beginMoving(id: comp.id)
                dragMode = .moving(id: comp.id)
            }
            return
        }

        dragMode = .panning(startOffset: viewModel.panOffset)
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let world = toWorld(value.location)
        let moved = hypot(value.translation.width, value.translation.height) > clickSlop

        switch dragMode {
        case .idle, .inert:
            break

        case .wiring:
            // Dragged from a dot and released: connect if over another dot, otherwise cancel.
            // Just clicked (no drag): stay in "click the second dot" mode.
            if moved {
                if let hit = pinHit(at: world) {
                    viewModel.handlePinClicked(componentId: hit.comp.id, pin: hit.pin)
                } else {
                    viewModel.cancelWiring()
                }
            }

        case .wiringClick:
            if let hit = pinHit(at: world) {
                viewModel.handlePinClicked(componentId: hit.comp.id, pin: hit.pin)
            } else {
                viewModel.cancelWiring()
            }

        case .moving(let id):
            if moved {
                viewModel.finishMovingComponent(id: id)
            } else if let comp = viewModel.circuit.components.first(where: { $0.id == id }),
                      comp.kind == .switchSPST {
                viewModel.toggleSwitch(componentId: id)
            }

        case .panning:
            if !moved {
                if let wireId = wireHit(at: world) {
                    viewModel.selectedWireId = wireId
                    viewModel.selectedComponentId = nil
                } else {
                    viewModel.selectedComponentId = nil
                    viewModel.selectedWireId = nil
                }
            }
        }

        dragMode = .idle
    }

    // MARK: - Hit testing (all in world coordinates)

    private func pinPoint(_ comp: CircuitComponent, _ pin: Pin) -> CGPoint {
        let p = comp.absolutePinPosition(pinIndex: pin.index)
        return CGPoint(x: p.x, y: p.y)
    }

    private func pinHit(at p: CGPoint) -> (comp: CircuitComponent, pin: Pin)? {
        var bestComp: CircuitComponent? = nil
        var bestPin: Pin? = nil
        var bestDist: CGFloat = pinHitRadius

        for comp in viewModel.circuit.components {
            for pin in comp.pins {
                let pos = pinPoint(comp, pin)
                let d = hypot(pos.x - p.x, pos.y - p.y)
                if d <= bestDist {
                    bestDist = d
                    bestComp = comp
                    bestPin = pin
                }
            }
        }

        if let c = bestComp, let pin = bestPin {
            return (comp: c, pin: pin)
        }
        return nil
    }

    private func snapPoint(_ world: CGPoint) -> CGPoint {
        if let hit = pinHit(at: world) {
            return pinPoint(hit.comp, hit.pin)
        }
        return world
    }

    private func componentHit(at p: CGPoint) -> CircuitComponent? {
        for comp in viewModel.circuit.components.reversed() {
            let dx = abs(p.x - CGFloat(comp.position.x))
            let dy = abs(p.y - CGFloat(comp.position.y))
            if dx <= bodyHalfSize && dy <= bodyHalfSize {
                return comp
            }
        }
        return nil
    }

    private func wireHit(at p: CGPoint) -> UUID? {
        for wire in viewModel.circuit.wires {
            guard let p1 = resolvePinCoordinate(wire.startPinId),
                  let p2 = resolvePinCoordinate(wire.endPinId) else { continue }
            let midX = (p1.x + p2.x) / 2.0
            let a = CGPoint(x: midX, y: p1.y)
            let b = CGPoint(x: midX, y: p2.y)
            let d1 = distance(from: p, toSegment: p1, a)
            let d2 = distance(from: p, toSegment: a, b)
            let d3 = distance(from: p, toSegment: b, p2)
            if min(d1, min(d2, d3)) < 7 {
                return wire.id
            }
        }
        return nil
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        t = min(max(t, 0), 1)
        let cx = a.x + t * dx
        let cy = a.y + t * dy
        return hypot(p.x - cx, p.y - cy)
    }

    // MARK: - Component & terminal visuals (display only)

    private func componentView(for comp: CircuitComponent) -> some View {
        let isSelected = viewModel.selectedComponentId == comp.id

        return ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 68, height: 68)
            }

            ComponentSymbolView(component: comp, isSelected: isSelected)

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
        .position(x: comp.position.x, y: comp.position.y)
    }

    private func pinTerminalView(component: CircuitComponent, pin: Pin) -> some View {
        let pos = component.absolutePinPosition(pinIndex: pin.index)
        let isDraftSource = viewModel.wireDraftStartPin?.pin.id == pin.id
        let isHovered = hoveredPinId == pin.id

        return ZStack {
            if isDraftSource || isHovered || viewModel.isWireMode {
                Circle()
                    .stroke(isDraftSource ? Color.green : Color.accentColor, lineWidth: 2)
                    .frame(width: isHovered ? 20 : 14, height: isHovered ? 20 : 14)
            }

            Circle()
                .fill(isDraftSource || isHovered ? Color.green : Color.accentColor)
                .frame(width: isHovered ? 10 : 8, height: isHovered ? 10 : 8)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
        }
        .position(x: pos.x, y: pos.y)
    }

    // MARK: - Canvas Drawing (Wires, Grid, Electrons)

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let step = viewModel.gridSize
        var dotPath = Path()
        let cols = Int(size.width / step) + 3
        let rows = Int(size.height / step) + 3
        let originX = floor(-viewModel.panOffset.x / step) * step
        let originY = floor(-viewModel.panOffset.y / step) * step

        for c in 0..<cols {
            for r in 0..<rows {
                let x = originX + CGFloat(c) * step
                let y = originY + CGFloat(r) * step
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
