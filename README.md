# MULTIMACSIM.v1 ⚡️
### Native macOS Circuit Simulator — B.Tech Year 1 Electrical Engineering Edition

A high-performance, native macOS schematic capture and SPICE circuit simulation application built in **Swift 6** and **SwiftUI**.

Designed specifically to cover the entire curriculum of **B.Tech 1st Year Basic Electrical Engineering (BEE) & Network Analysis**.

---

## How to use

- **New / Open / Save** (toolbar, or `Cmd+N` / `Cmd+O` / `Cmd+S` / `Shift+Cmd+S`): the app starts with a blank circuit. Circuits are saved as `.msim` files.
- **Add parts:** drag a part from the left sidebar onto the canvas, or click it to drop it at the next free spot.
- **Move parts:** drag a part anywhere on the canvas. Drag empty space to pan.
- **Connect:** drag from one terminal dot to another dot and release. You can also click one dot, then the other. Parts whose terminals land exactly on each other connect automatically.
- **Delete a wire:** click it, then press `Delete`.

## Keyboard Shortcuts

- `W`: Toggle Wire Mode
- `Space`: Run / Pause Simulation
- `R`: Rotate Selected Component 90°
- `Backspace` / `Delete`: Delete Selected Component or Wire
- `Esc`: Cancel Active Wire Drafting

---

## How to Run MULTIMACSIM.v1

```bash
cd MultiSim
swift run
```
Or open in Xcode:
```bash
open MultiSim/Package.swift
```
*(Press `Cmd + R` in Xcode)*
