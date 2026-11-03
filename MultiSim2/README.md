# MULTIMACSIM.v1.1 ⚡️
### Native macOS Circuit Simulator — B.Tech Year 1 Electrical Engineering Edition

A high-performance, native macOS schematic capture and SPICE circuit simulation application built in **Swift 6** and **SwiftUI**.

Designed specifically to cover the entire curriculum of **B.Tech 1st Year Basic Electrical Engineering (BEE) & Network Analysis**.

---

## How to use

### Wiring things together

Every connection in the app is a real electrical net, and the app tries hard to make one for you.

- **Magnetic terminals.** While you drag a part, its terminals reach out and grab a nearby terminal (18 pt) or a wire that passes close by (10 pt). You will see the part settle into place, and the wire appears the moment you let go.
- **Drop-on-wire = T-junction.** Landing a terminal on top of an existing wire taps into it. The junction is drawn as a dot and both sides of the wire join the same node.
- **Auto-Connect Facing Pins** (`Shift+Cmd+A`, also in the left palette and the right inspector). Wires every pair of terminals on the same row or column that are already pointing at each other within 60 pt. Use it after dropping a row of parts to turn a sketch into a circuit in one keystroke.
- **Snap All to Grid.** Tidies every part onto the grid and re-checks every connection, so parts that were a pixel off line up and connect.
- **Manual wire.** Press `W`, then click a terminal dot and click the other one (or drag from one to the other). `Esc` abandons the draft.
- **Wires are drawn, never stored.** The path of a wire is recomputed from the live positions of the two terminals it joins, so dragging a part makes its wires follow. Routes leave each pin straight along its lead, turn only at right angles, and land on grid lines - which is what keeps a busy schematic readable instead of tangled.

An open terminal is drawn in orange, so "what is not connected yet" is always visible. The inspector lists every terminal of the selected part with the net it belongs to and tells you how far the nearest matching terminal is.

### Parts

42 parts in six palette sections, with a search box on top:

- **Measuring Instruments** - ammeter (in series), voltmeter (across), multimeter with a V / A / Ω mode switch, ohmmeter, wattmeter (current coil + pressure coil), galvanometer with a needle that deflects with the current.
- **Sources & Ground** - DC supply, AC supply, DC current source, clock, function generator (sine / pulse / triangle), ground.
- **Passives & Loads** - resistor, capacitor, electrolytic and trimmer capacitors, inductor, potentiometer (three terminals: A, B, wiper), rheostat, switch, lamp, fuse (blows on overcurrent, resettable), thermistor and photo-resistor that follow temperature and light.
- **Semiconductors** - diode, LED, Zener, Schottky, NPN and PNP transistors.
- **Analog & Logic ICs** - op-amp, VCVS, VCCS, AND / OR / NOT / NAND / NOR / XOR / XNOR / buffer.
- **Probes & Test** - a test probe that reports the voltage of whatever net it is tied to.

The palette also holds the wiring tools (Select / Wire / Auto-Connect Facing Pins / Snap All to Grid), a short "how parts connect" note, and the lab examples.

Live readings appear on the part itself while the simulation runs, and the inspector shows the voltage across, current through and power of the selected part.

### Lab examples (pre-wired)

The bottom of the left palette loads a complete, already-connected circuit, so you can see the wiring rules working before you draw anything: Lab 1 KVL & KCL, Lab 2 Thevenin/Norton, Lab 3 Maximum Power Transfer (potentiometer as a variable load), Lab 4 Series RLC Resonance, Lab 5 Full-Wave Bridge Rectifier, Lab 6 Ohm's Law with Ammeter & Voltmeter, Lab 7 Potentiometer as Potential Divider, plus a half-wave rectifier, an RC low-pass filter and an interactive LED & switch. **The app opens on Lab 6**; `Cmd+N` starts from blank.

### Files

- **New / Open / Save** (toolbar, or `Cmd+N` / `Cmd+O` / `Cmd+S` / `Shift+Cmd+S`). Circuits are saved as `.msim` files. **SPICE** in the toolbar writes an ngspice/LTspice-compatible `.cir` netlist, including the instrument models.

## Keyboard Shortcuts

- `W`: Toggle Wire Mode
- `Shift+Cmd+A`: Auto-Connect Facing Pins
- `Space`: Run / Pause Simulation
- `R`: Rotate Selected Component 90°
- `Backspace` / `Delete`: Delete Selected Component or Wire
- `Esc`: Cancel Active Wire Drafting

---

## How to Run MULTIMACSIM.v1.1

```bash
cd MultiSim
swift run
```
Or open in Xcode:
```bash
open MultiSim/Package.swift
```
*(Press `Cmd + R` in Xcode)*

## Tests

```bash
swift test
```

29 engine tests: MNA solver correctness, wiring geometry (orthogonality, snapping, taps, no doubled-back runs) and instrument behaviour (meter readings, ideal-meter loading, DMM modes, potentiometer divider, fuse blow/reset, sensors, SPICE export).
