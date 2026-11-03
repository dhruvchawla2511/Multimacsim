import SwiftUI
import MultiSimEngine

/// Sidebar component palette: every part in the engine, grouped, with the wiring tools and lab examples.
public struct ComponentPaletteView: View {
    @ObservedObject var viewModel: CircuitEditorViewModel
    @State private var searchText: String = ""

    private static let orderedCategories: [PartCategory] = [
        .instruments, .probes, .sources, .passives, .semiconductors, .analogLogic
    ]

    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search 40+ parts...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    toolsSection
                    labSection

                    ForEach(Self.orderedCategories, id: \.self) { category in
                        categorySection(category)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 250)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Tools

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WIRING TOOLS")
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
            toolRow(title: "Auto-Connect Facing Pins", icon: "link") {
                viewModel.autoConnectFacingPins()
            }
            toolRow(title: "Snap All to Grid", icon: "grid") {
                viewModel.snapAllToGrid()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("How parts connect:")
                    .font(.system(size: 10, weight: .semibold))
                Text("• Drag a part near another — terminals snap together and a wire appears.")
                Text("• Drop a part onto an existing wire — it taps into that net.")
                Text("• Or drag from dot to dot with the Wire tool (W).")
                Text("• Wires always run straight along the grid, following the terminals.")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
    }

    // MARK: - Lab examples

    private var labSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAB EXAMPLES (PRE-WIRED)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(PresetType.allCases) { preset in
                Button {
                    viewModel.loadPreset(type: preset)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flask")
                            .frame(width: 16)
                        Text(shortTitle(preset))
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.10)))
            }
        }
    }

    private func shortTitle(_ preset: PresetType) -> String {
        preset.rawValue.replacingOccurrences(of: "Lab ", with: "L").replacingOccurrences(of: "Example: ", with: "")
    }

    // MARK: - Category list

    private func categorySection(_ category: PartCategory) -> some View {
        let items = ComponentKind.allCases.filter { $0.category == category && matchesSearch($0) }
        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(category.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(items.count)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    ForEach(items, id: \.self) { kind in
                        partRow(kind)
                    }
                }
            }
        }
    }

    private func matchesSearch(_ kind: ComponentKind) -> Bool {
        searchText.isEmpty
            || kind.paletteLabel.localizedCaseInsensitiveContains(searchText)
            || kind.rawValue.localizedCaseInsensitiveContains(searchText)
    }

    private func partRow(_ kind: ComponentKind) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.sfSymbol)
                .frame(width: 16)
                .foregroundStyle(kind.isInstrument ? Color.orange : Color.accentColor)
            Text(kind.paletteLabel)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(kind.isInstrument ? Color.orange.opacity(0.07) : Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Click: add at the next free spot. Drag: drop it exactly where you want.
            viewModel.addComponent(kind: kind, at: viewModel.nextFreePosition())
        }
        .draggable(kind.rawValue)
        .help("\(kind.paletteLabel) — click to place, or drag onto the canvas")
    }

    private func toolRow(title: String, icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
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
}
