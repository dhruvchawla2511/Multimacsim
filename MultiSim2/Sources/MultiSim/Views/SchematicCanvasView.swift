import SwiftUI
import MultiSimEngine

/// Interactive schematic canvas.
///
/// All mouse handling lives in ONE gesture on the canvas container. On mouse-down it decides what is
/// under the pointer (a terminal pin, a component body, a wire, or empty space) and then drags, wires
/// or pans accordingly. The drawn layers never receive clicks themselves, so nothing can steal a drag.
///
/// Wire geometry is never stored: every wire is re-routed from the live terminal positions through
/// `Circuit.wirePath`, so a connection keeps following the part it is attached to and always runs
/// along straight, grid-aligned segments.
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
                let p = toWorld(location)
                viewModel.addComponent(kind: kind, at: Point2D(x: p.x, y: p.y))
                return true
            }
            .clipped()
        }
    }

    // MARK: - Layers

    private var worldLayer: some View {
        let connected = connectedPinIds
        return ZStack {
            Canvas { context, size in
                drawGrid(context: context, size: size)
                drawWires(context: context)
                drawCurrentAnimation(context: context)
                drawJunctionDots(context: context)
            }
            .drawingGroup()

            // Rubber-band preview while drawing a wire: the same router the finished wire will use.
            if let draftPath = draftWirePath() {
                cgPath(draftPath)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
            }

            ForEach(viewModel.circuit.components) { comp in
                componentView(for: comp)
            }

            ForEach(viewModel.circuit.components) { comp in
                ForEach(comp.pins) { pin in
                    pinTerminalView(component: comp, pin: pin, floating: !connected.contains(pin.id))
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
                Text("Drag a part from the left onto the canvas, or click a part to add it.\nParts snap together: get two terminals close and they connect themselves.")
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
                // Move by the screen-space delta from where the part was picked up; the view model
                // then nudges it so a terminal grabs whatever it is near.
                let grabOrigin = viewModel.dragOrigin(for: id) ?? comp.position
                let target = Point2D(x: grabOrigin.x + Double(value.translation.width),
                                     y: grabOrigin.y + Double(value.translation.height))
                viewModel.updateComponentPosition(id: id, newPosition: target)
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
            // Dragged from a dot and released: connect to the dot, tap the wire underneath, or cancel.
            if moved {
                if let hit = pinHit(at: world) {
                    viewModel.handlePinClicked(componentId: hit.comp.id, pin: hit.pin)
                } else if let tap = wireTapHit(at: world) {
                    viewModel.completeWireDraft(ontoWire: tap.wire, at: tap.point)
                } else {
                    viewModel.cancelWiring()
                }
            }

        case .wiringClick:
            if let hit = pinHit(at: world) {
                viewModel.handlePinClicked(componentId: hit.comp.id, pin: hit.pin)
            } else if let tap = wireTapHit(at: world) {
                viewModel.completeWireDraft(ontoWire: tap.wire, at: tap.point)
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

    private var grid: Double { Double(viewModel.gridSize) }

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

    /// A point on an existing wire near `p` - releasing a draft here taps into that net.
    private func wireTapHit(at p: CGPoint) -> (wire: Wire, point: Point2D)? {
        guard let draft = viewModel.wireDraftStartPin else { return nil }
        let tap = AutoConnect.nearestTapPoint(
            from: Point2D(x: p.x, y: p.y),
            in: viewModel.circuit,
            grid: grid,
            tolerance: 14,
            ignoring: nil
        )
        guard let tap else { return nil }
        // Never tap a wire into the very wire being drawn from.
        guard tap.wire.startPinId != draft.pin.id, tap.wire.endPinId != draft.pin.id else { return nil }
        return (tap.wire, tap.point)
    }

    /// Snap the draft cursor onto a terminal, onto a wire, or onto the grid.
    private func snapPoint(_ world: CGPoint) -> CGPoint {
        if let hit = pinHit(at: world) {
            return pinPoint(hit.comp, hit.pin)
        }
        if let tap = wireTapHit(at: world) {
            return CGPoint(x: tap.point.x, y: tap.point.y)
        }
        return CGPoint(x: WireRouter.snap(Double(world.x), to: grid),
                       y: WireRouter.snap(Double(world.y), to: grid))
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
        let target = Point2D(x: p.x, y: p.y)
        for wire in viewModel.circuit.wires {
            guard let path = routedPoints(wire) else { continue }
            if WireRouter.distance(from: target, toPolyline: path) < 7 {
                return wire.id
            }
        }
        return nil
    }

    // MARK: - Wire geometry

    /// The drawn polyline of a stored wire, computed from where its terminals are right now.
    private func routedPoints(_ wire: Wire) -> [Point2D]? {
        viewModel.circuit.wirePath(wire, grid: grid)
    }

    private func cgPath(_ points: [Point2D]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for p in points.dropFirst() {
            path.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        return path
    }

    /// Live preview of the wire being drawn, routed exactly like the finished one.
    private func draftWirePath() -> [Point2D]? {
        guard let draft = viewModel.wireDraftStartPin,
              let current = viewModel.wireDraftCurrentPoint,
              let startComp = viewModel.circuit.components.first(where: { $0.id == draft.componentId }) else { return nil }

        let start = startComp.absolutePinPosition(pinIndex: draft.pin.index)
        let startDir = startComp.pinExitDirection(pinIndex: draft.pin.index)
        let cursor = Point2D(x: current.x, y: current.y)

        if let hit = pinHit(at: current), hit.pin.id != draft.pin.id {
            let end = hit.comp.absolutePinPosition(pinIndex: hit.pin.index)
            return WireRouter.route(start: start, startDir: startDir, end: end,
                                    endDir: hit.comp.pinExitDirection(pinIndex: hit.pin.index),
                                    grid: grid)
        }
        if let tap = wireTapHit(at: current) {
            return WireRouter.routeToTap(start: start, startDir: startDir, tap: tap.point, grid: grid)
        }
        // Free end: leave along the pin's lead, then run straight to the cursor.
        let toward: PinDirection
        if cursor.x == start.x && cursor.y == start.y {
            toward = startDir
        } else if abs(cursor.x - start.x) >= abs(cursor.y - start.y) {
            toward = cursor.x >= start.x ? .right : .left
        } else {
            toward = cursor.y >= start.y ? .down : .up
        }
        return WireRouter.route(start: start, startDir: startDir, end: cursor, endDir: toward, grid: grid)
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
                if let value = valueText(for: comp) {
                    Text(value)
                        .font(.system(size: 10, weight: comp.kind.showsLiveReading ? .bold : .regular, design: .monospaced))
                        .foregroundStyle(comp.kind.showsLiveReading ? Color.orange : Color.secondary)
                }
            }
            .offset(y: labelOffsetY(for: comp))
        }
        .frame(width: 60, height: 60)
        .position(x: comp.position.x, y: comp.position.y)
    }

    private func pinTerminalView(component: CircuitComponent, pin: Pin, floating: Bool) -> some View {
        let pos = component.absolutePinPosition(pinIndex: pin.index)
        let isDraftSource = viewModel.wireDraftStartPin?.pin.id == pin.id
        let isHovered = hoveredPinId == pin.id
        let isFloating = floating && !isDraftSource

        return ZStack {
            if isDraftSource || isHovered || viewModel.isWireMode {
                Circle()
                    .stroke(isDraftSource ? Color.green : Color.accentColor, lineWidth: 2)
                    .frame(width: isHovered ? 20 : 14, height: isHovered ? 20 : 14)
            }

            Circle()
                .fill(isDraftSource || isHovered ? Color.green : (isFloating ? Color.orange : Color.accentColor))
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
            guard let points = routedPoints(wire), points.count >= 2 else { continue }
            let isSelected = viewModel.selectedWireId == wire.id
            context.stroke(cgPath(points),
                           with: .color(isSelected ? Color.accentColor : wireColor(for: wire)),
                           lineWidth: isSelected ? 3.0 : 2.0)
        }
    }

    private func drawCurrentAnimation(context: GraphicsContext) {
        guard viewModel.isSimulating else { return }

        for wire in viewModel.circuit.wires {
            guard abs(wire.runtimeCurrent) > 1e-6, let points = routedPoints(wire) else { continue }

            let dotSpacing: CGFloat = 20.0
            let phase = CGFloat(viewModel.animationPhase.truncatingRemainder(dividingBy: Double(dotSpacing)))
            let dir: CGFloat = wire.runtimeCurrent >= 0 ? 1.0 : -1.0

            // Dots travel from the far end towards the start when the current is negative.
            let ordered: [Point2D] = dir > 0 ? points : points.reversed()

            for i in 0..<(ordered.count - 1) {
                let start = CGPoint(x: ordered[i].x, y: ordered[i].y)
                let end = CGPoint(x: ordered[i + 1].x, y: ordered[i + 1].y)
                let dx = end.x - start.x
                let dy = end.y - start.y
                let len = hypot(dx, dy)
                if len < 2 { continue }

                var dist = (phase * dir).truncatingRemainder(dividingBy: dotSpacing)
                if dist < 0 { dist += dotSpacing }

                while dist < len {
                    let t = dist / len
                    let dotX = start.x + t * dx
                    let dotY = start.y + t * dy

                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: dotX - 2.5, y: dotY - 2.5, width: 5, height: 5))
                    context.fill(dot, with: .color(.yellow.opacity(0.85)))

                    dist += dotSpacing
                }
            }
        }
    }

    /// Dots where wires genuinely join: T-junction taps and terminals with more than one wire.
    private func drawJunctionDots(context: GraphicsContext) {
        var pinCounts = [UUID: Int]()
        for wire in viewModel.circuit.wires {
            pinCounts[wire.startPinId, default: 0] += 1
            pinCounts[wire.endPinId, default: 0] += 1
            for tap in wire.waypoints {
                var dot = Path()
                dot.addEllipse(in: CGRect(x: tap.x - 3.5, y: tap.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(.primary))
            }
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

    /// Terminals that already carry at least one wire; the rest are drawn in warning orange.
    private var connectedPinIds: Set<UUID> {
        var ids = Set<UUID>()
        for wire in viewModel.circuit.wires {
            ids.insert(wire.startPinId)
            ids.insert(wire.endPinId)
        }
        return ids
    }

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

    /// Instruments show what they are measuring right now; other parts show their rating.
    private func valueText(for comp: CircuitComponent) -> String? {
        if comp.kind.showsLiveReading {
            return viewModel.readingText(for: comp)
        }
        switch comp.kind {
        case .resistor, .rheostat, .lamp, .thermistor, .photoResistor:
            return EngineeringFormatter.resistance(comp.value)
        case .capacitor, .electrolyticCapacitor, .trimmerCapacitor:
            return EngineeringFormatter.capacitance(comp.value)
        case .inductor:
            return EngineeringFormatter.inductance(comp.value)
        case .potentiometer:
            return "\(EngineeringFormatter.resistance(comp.value)) · \(Int((MNASolver.wiperRatio(of: comp)) * 100))%"
        case .fuse:
            return comp.stateBool ? EngineeringFormatter.current(comp.fuseRating) : "BLOWN"
        case .dcVoltageSource, .dcCurrentSource:
            return "\(comp.value)V"
        case .acVoltageSource:
            return "\(comp.value)V @ \(Int(comp.secondaryValue > 0 ? comp.secondaryValue : 60))Hz"
        case .clockSource, .functionGenerator:
            return "\(comp.value)V @ \(Int(comp.secondaryValue > 0 ? comp.secondaryValue : 1000))Hz"
        case .switchSPST:
            return comp.stateBool ? "CLOSED" : "OPEN"
        case .led:
            return comp.ledColor.rawValue.capitalized
        case .zenerDiode:
            return "\(comp.secondaryValue > 0 ? comp.secondaryValue : 5.1)V Zener"
        case .diode, .schottkyDiode:
            return comp.kind == .schottkyDiode ? "Schottky" : "1N4148"
        case .vcvs:
            return "Gain: \(comp.value)x"
        case .vccs:
            return "gm: \(comp.value) S"
        case .bjtNPN, .bjtPNP:
            return "β: \(Int(comp.secondaryValue > 0 ? comp.secondaryValue : 100))"
        case .multimeter:
            return (MeterMode(rawValue: comp.modeIndex) ?? .voltage).label
        default:
            return nil
        }
    }
}
