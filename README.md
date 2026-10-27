# Multimacsim
This is an alternative created for Mac users to use software like Multisim and Tinkercad. This was developed with respect to students on Mac who can't access the software.

# MULTIMACSIM.v1.1 ⚡️
### Native macOS Circuit Simulator — B.Tech Year 1 Electrical Engineering Edition

A high-performance, native macOS schematic capture and SPICE circuit simulation application built in **Swift 6** and **SwiftUI**.

Designed specifically to cover the entire curriculum of **B.Tech 1st Year Basic Electrical Engineering (BEE) & Network Analysis**.

---

## What's New in MULTIMACSIM.v1.1

### 1. Completely Overhauled Wire Connection System
- **Exact Coordinate Pin Alignment:** Fixed the coordinate displacement bug so pins snap and connect precisely at terminal leads.
- **Generous 28px Magnetic Hitbox:** Terminal dots now have a wide magnetic click area, making connecting components effortless with trackpad or mouse.
- **Dedicated Wire Tool (`W`):** Toggle wire mode from the toolbar or press `W`.
- **Magnetic Auto-Snap & Glowing Rings:** When drafting a wire, hovering near any terminal highlights it with a green glowing ring and snaps the rubber-band line directly to its center.
- **Interactive Wiring HUD Banner:** Displays real-time feedback at the top of the canvas (e.g. `Wiring from R1 pin 'A'... Click target pin to connect` with a `Cancel (Esc)` button).

### 2. Live On-Canvas Simulation Testing & Diagnostics
- **Live Node Voltage Badges:** Toggle the **"Voltages"** button in the toolbar to see live voltage overlays on every node directly on the schematic (e.g. `[ 12.0V ]`, `[ 6.0V ]`, `[ 0V ]`).
- **One-Click Circuit Diagnostics ("Run Test"):** Click **"Run Test"** in the toolbar to open the diagnostic inspection sheet:
  - **Ground Check:** Warns if circuit is missing a Ground (0V) reference.
  - **Floating Pin Detection:** Alerts you to any open/unconnected terminals.
  - **Closed-Loop Continuity Check:** Verifies current circulation.
  - **DC Operating Point (.OP) Table:** Complete tabular breakdown of all Node Voltages, Branch Currents, and Power Dissipations.

### 3. 5 Pre-Loaded Academic Lab Experiments
Under the **Examples** menu in the toolbar:
1. **Lab 1: KVL & KCL Verification** ($I_{\text{total}} = I_{R2} + I_{R3}$, $\sum V = 0$).
2. **Lab 2: Thevenin's & Norton's Theorem** ($V_{th} = 16\text{V}$, $R_{th} = 8\,\Omega$, $I_N = 2\text{A}$).
3. **Lab 3: Maximum Power Transfer** ($P_{RL}$ vs $R_L$ with interactive slider).
4. **Lab 4: Series RLC Resonance** ($f_0 \approx 1591.5\text{ Hz}$).
5. **Lab 5: Full-Wave Bridge Rectifier with Filter** (4-diode Graetz bridge with capacitor filter).

### 4. AC Phasor & Power Factor Meter
Click **"Phasor & PF"** in the toolbar to view the live polar vector diagram, active power ($P$), reactive power ($Q$), apparent power ($S$), and power factor ($\cos\phi$).

---

## Keyboard Shortcuts

- `W`: Toggle Wire Mode
- `Space`: Run / Pause Simulation
- `R`: Rotate Selected Component 90°
- `Backspace` / `Delete`: Delete Selected Component or Wire
- `Esc`: Cancel Active Wire Drafting

---

## How to Run MULTIMACSIM.v1.1

```bash
cd /Users/dhruv/Projects/MultiSim
swift run
```
Or open in Xcode:
```bash
open /Users/dhruv/Projects/MultiSim/Package.swift
```
*(Press `Cmd + R` in Xcode)*
