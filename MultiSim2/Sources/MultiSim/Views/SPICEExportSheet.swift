import SwiftUI
import AppKit
import MultiSimEngine

/// Sheet modal to view, copy, and export standard SPICE netlists (.cir).
public struct SPICEExportSheet: View {
    public let circuit: Circuit
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false

    private var netlistText: String {
        SPICEExporter.export(circuit: circuit)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("SPICE Netlist Export", systemImage: "doc.text.fill")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }

            Text("Standard SPICE 3 / ngspice / LTspice compatible circuit deck.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Netlist Code Editor View
            ScrollView {
                Text(netlistText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            HStack {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(netlistText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        copied = false
                    }
                }) {
                    Label(copied ? "Copied!" : "Copy to Clipboard", systemImage: copied ? "checkmark" : "doc.on.doc")
                }

                Spacer()

                Button("Save As .cir...") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = []
                    panel.nameFieldStringValue = "circuit.cir"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? netlistText.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 520, height: 420)
    }
}
