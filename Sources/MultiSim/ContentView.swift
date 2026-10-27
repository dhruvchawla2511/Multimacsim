import SwiftUI
import MultiSimEngine

public struct ContentView: View {
    @ObservedObject var viewModel: CircuitEditorViewModel
    @State private var showSPICEExport: Bool = false
    @State private var showPhasorMeter: Bool = false

    public init(viewModel: CircuitEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            ComponentPaletteView(viewModel: viewModel)
        } detail: {
            HStack(spacing: 0) {
                // Center Schematic Canvas with bottom Oscilloscope
                ZStack(alignment: .bottom) {
                    SchematicCanvasView(viewModel: viewModel)

                    if viewModel.showOscilloscope {
                        OscilloscopeView(viewModel: viewModel)
                            .padding(12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                // Right Inspector
                InspectorView(viewModel: viewModel)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                // Play / Pause Simulation
                Button(action: { viewModel.toggleSimulation() }) {
                    Label(viewModel.isSimulating ? "Pause" : "Run",
                          systemImage: viewModel.isSimulating ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                .help("Run / Pause Simulation (Space)")

                // Single Step
                Button(action: { viewModel.stepSimulationSingle() }) {
                    Label("Step", systemImage: "forward.frame.fill")
                }
                .disabled(viewModel.isSimulating)
                .help("Step Simulation")

                // Reset
                Button(action: { viewModel.resetSimulation() }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .help("Reset Circuit State")

                Divider()

                // Simulation Speed
                Picker("Speed", selection: $viewModel.simulationSpeed) {
                    Text("0.25x").tag(0.25)
                    Text("0.5x").tag(0.5)
                    Text("1.0x").tag(1.0)
                    Text("2.0x").tag(2.0)
                }
                .frame(width: 90)

                Divider()

                // File: New / Open / Save (like a paint program)
                Button(action: { viewModel.newDocument() }) {
                    Label("New", systemImage: "doc.badge.plus")
                }
                .help("New blank circuit (Cmd+N)")

                Button(action: { viewModel.openDocument() }) {
                    Label("Open", systemImage: "folder")
                }
                .help("Open a saved circuit (Cmd+O)")

                Button(action: { viewModel.saveDocument() }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save circuit (Cmd+S)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                // Wire Tool Toggle
                Button(action: { viewModel.isWireMode.toggle() }) {
                    Label("Wire Mode", systemImage: "pencil.line")
                }
                .tint(viewModel.isWireMode ? .green : .secondary)
                .keyboardShortcut("w", modifiers: [])
                .help("Toggle Wire Mode (W)")

                // Toggle On-Canvas Node Voltages
                Button(action: { viewModel.showNodeVoltages.toggle() }) {
                    Label("Voltages", systemImage: "number.circle")
                }
                .tint(viewModel.showNodeVoltages ? .accentColor : .secondary)
                .help("Show/Hide On-Canvas Voltage Badges")

                // Circuit Simulation Test & Diagnostics
                Button(action: { viewModel.showDiagnosticsSheet = true }) {
                    Label("Run Test", systemImage: "checkmark.shield.fill")
                }
                .help("Run Circuit Diagnostic Check & DC Operating Point (.OP)")

                Divider()

                // Toggle Oscilloscope
                Button(action: {
                    withAnimation {
                        viewModel.showOscilloscope.toggle()
                    }
                }) {
                    Label("Oscilloscope", systemImage: "waveform.path.ecg")
                }
                .tint(viewModel.showOscilloscope ? .accentColor : .secondary)

                // Phasor & AC Power Meter
                Button(action: { showPhasorMeter = true }) {
                    Label("Phasor & PF", systemImage: "dial.low.fill")
                }
                .help("Open Phasor & AC Power Factor Meter")

                // Rotate Component
                Button(action: { viewModel.rotateSelected() }) {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .keyboardShortcut("r", modifiers: [])
                .disabled(viewModel.selectedComponentId == nil)
                .help("Rotate 90° (R)")

                // Delete
                Button(action: { viewModel.deleteSelected() }) {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(viewModel.selectedComponentId == nil && viewModel.selectedWireId == nil)
                .help("Delete (Backspace)")

                // Export SPICE
                Button(action: { showSPICEExport = true }) {
                    Label("SPICE", systemImage: "doc.text")
                }
                .help("Export SPICE Netlist (.cir)")
            }
        }
        .sheet(isPresented: $showSPICEExport) {
            SPICEExportSheet(circuit: viewModel.circuit)
        }
        .sheet(isPresented: $showPhasorMeter) {
            PhasorMeterView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showDiagnosticsSheet) {
            CircuitDiagnosticsSheet(viewModel: viewModel)
        }
        .navigationTitle(viewModel.documentName)
        .frame(minWidth: 1050, minHeight: 700)
    }
}
