import Foundation
import MultiSimEngine

/// Editing a part's numbers (resistance, capacitance, source voltage, frequency ...) while the circuit runs.
extension CircuitEditorViewModel {

    /// Parts are reference types, so SwiftUI is not told when one changes in place. Call this after any edit.
    public func refreshAfterEdit() {
        objectWillChange.send()
    }

    private func component(_ id: UUID) -> CircuitComponent? {
        circuit.components.first(where: { $0.id == id })
    }

    /// Sets one number on one part, clamped to its legal range. Returns the value actually applied,
    /// or nil if the part or slot does not exist / the input is not finite.
    /// The solver reads values every step, so the change shows up on the very next frame - no restart needed.
    @discardableResult
    public func setParameter(componentId: UUID, slot: ParameterSlot, to newValue: Double) -> Double? {
        guard let comp = component(componentId),
              let spec = comp.kind.parameterSpec(slot),
              newValue.isFinite else { return nil }
        let applied = spec.clamp(newValue)
        switch slot {
        case .primary: comp.value = applied
        case .secondary: comp.secondaryValue = applied
        }
        objectWillChange.send()
        return applied
    }

    /// One click of the up/down stepper (also bound to ] and [).
    public func stepParameter(componentId: UUID, slot: ParameterSlot, up: Bool) {
        guard let comp = component(componentId),
              let spec = comp.kind.parameterSpec(slot) else { return }
        let current = slot == .primary ? comp.value : comp.secondaryValue
        setParameter(componentId: componentId, slot: slot, to: spec.stepped(from: current, up: up))
    }

    /// Keyboard path: step the selected part's main value.
    public func stepSelectedPrimary(up: Bool) {
        guard let id = selectedComponentId else { return }
        stepParameter(componentId: id, slot: .primary, up: up)
    }

    /// Wiper / switch / mode edits that do not go through a ParameterSpec still need a redraw.
    public func setWiper(componentId: UUID, to ratio: Double) {
        guard let comp = component(componentId) else { return }
        comp.secondaryValue = min(max(ratio, 0.001), 0.999)
        objectWillChange.send()
    }
}
