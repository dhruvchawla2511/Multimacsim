import SwiftUI
import MultiSimEngine

/// Sidebar component palette containing all standard electronic parts categorized for quick placement.
public struct ComponentPaletteView: View {
    @ObservedObject var viewModel: CircuitEditorViewModel
    @State private var searchText: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search components...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .bottom)

            // Category list
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    toolsSection

                    categorySection(title: "Sources & Ground", items: [
                        (.ground, "Ground (0V)", "arrow.down.to.line"),
                        (.dcVoltageSource, "DC Voltage Source", "battery.100.bolt"),
                        (.acVoltageSource, "AC Sine Source", "waveform"),
                        (.clockSource, "Clock Pulse", "metronome"),
                        (.dcCurrentSource, "Current Source", "arrow.up.circle")
                    ])

                    categorySection(title: "Basic Passives", items: [
                        (.resistor, "Resistor", "alternatingcurrent"),
                        (.capacitor, "Capacitor", "pause"),
                        (.inductor, "Inductor", "rotate.right"),
                        (.potentiometer, "Potentiometer", "slider.horizontal.3"),
                        (.switchSPST, "SPST Switch", "switch.2")
                    ])

                    categorySection(title: "Controlled Sources (BEE)", items: [
                        (.vcvs, "VCVS (Voltage Controlled)", "diamond.fill"),
                        (.vccs, "VCCS (Current Controlled)", "diamond")
                    ])

                    categorySection(title: "Semiconductors", items: [
                        (.diode, "Diode (1N4148)", "arrowtriangle.right.fill"),
                        (.led, "LED", "lightbulb.fill"),
                        (.zenerDiode, "Zener Diode", "bolt.fill"),
                        (.bjtNPN, "NPN Transistor", "arrow.up.right.circle"),
                        (.bjtPNP, "PNP Transistor", "arrow.down.right.circle")
                    ])

                    categorySection(title: "Analog & Logic ICs", items: [
                        (.opAmp, "Operational Amplifier", "triangle.fill"),
                        (.logicAND, "AND Gate", "square.split.diagonal.2x2"),
                        (.logicOR, "OR Gate", "shield"),
                        (.logicNOT, "NOT Inverter", "circle.slash"),
                        (.logicNAND, "NAND Gate", "square.split.diagonal"),
                        (.logicNOR, "NOR Gate", "shield.slash"),
                        (.logicXOR, "XOR Gate", "divide")
                    ])
                }
                .padding(10)
            }
        }
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TOOLS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            toolRow(title: "Select / Move", icon: "cursorarrow", active: !viewModel.isWireMode) {
                viewModel.isWireMode = false
                viewModel.cancelWiring()
            }
            toolRow(title: "Wire (W)", icon: "pencil.line", active: viewModel.isWireMode) {
                viewModel.isWireMode = true
            }

            Text("Drag from a terminal dot to another dot to connect. Click a wire to select it, then Delete.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
    }

    private func toolRow(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(active ? Color.accentColor : Color.primary.opacity(0.04))
        )
    }

    private func categorySection(title: String, items: [(kind: ComponentKind, name: String, icon: String)]) -> some View {
        let filtered = items.filter { item in
            searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
        }

        return Group {
            if !filtered.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(filtered, id: \.kind) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .frame(width: 16)
                                .foregroundStyle(Color.accentColor)
                            Text(item.name)
                                .font(.system(size: 12))
                            Spacer()
                            Image(systemName: "plus")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Click: add at the next free spot. Drag: drop it exactly where you want.
                            viewModel.addComponent(kind: item.kind, at: viewModel.nextFreePosition())
                        }
                        .draggable(item.kind.rawValue)
                    }
                }
            }
        }
    }
}
