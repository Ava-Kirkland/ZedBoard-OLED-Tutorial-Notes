# Video 1 — SPI Controller

**Video:** [SPI Controller](https://www.youtube.com/watch?v=V8jW81VaLOg&list=PLXHMvqUANAFOviU0J8HSp0E91lLJInzX1&index=8)  
**Vivado 2025 differences:** None — follow along as-is.

---

## Overview

This video builds a reusable SPI controller module in Verilog and verifies it using Vivado's behavioral simulation. The SPI controller is a foundational building block used in every subsequent OLED video.

---

## Project File Structure

Use this folder layout for every video project in the series:

```
Project Folder/
├── vivado/    ← Vivado project goes here
└── ws/        ← Vitis workspace goes here
```

---

## Key Concepts

**SPI (Serial Peripheral Interface)** sends data one bit at a time over a serial clock. For the ZedBoard's OLED:
- Maximum SPI clock: **10 MHz** (OLED datasheet limit)
- The on-board Zynq clock is 100 MHz — divide by 10 to get 10 MHz SPI clock
- Data is **loaded on the falling edge** and **read on the rising edge** of `spi_clock`
- Data is sent **MSB first**, 1 byte (8 bits) at a time

**Clock Enable (CE):** `spi_clock` only runs when `CE` is high — it is gated off when the controller is idle. This prevents spurious clock edges from reaching the OLED between transmissions.

---

## Simulation Notes

At the start of a behavioral simulation, type in the Tcl Console:

```tcl
restart
```

This clears the auto-generated initial signal values so the waveform starts from a clean state.

![TCL Console restart](images/Screenshot%202026-06-16%20093439.png)

---

## Verified Behavior

**SPI clock at 10 MHz:**

![10MHz SPI clock](images/Screenshot%202026-06-16%20093949.png)

**Byte `0xA7` (`10100111`) transmitted correctly — data loaded on falling edge, read on rising edge:**

![A7 data transmission](images/Screenshot%202026-06-16%20102701.png)

**Clock Enable signal gating `spi_clock`:**

![Clock enable gating](images/Screenshot%202026-06-16%20104715.png)

---

## Important Verilog Note

In the SPI controller state machine, use **non-blocking assignments** (`<=`) for every register update — including `CE`:

```verilog
// CORRECT
CE <= 0;

// WRONG — mixing blocking and non-blocking in a clocked always block
CE = 0;
```

Mixing `=` and `<=` for the same signal inside a clocked `always` block causes undefined simulation behavior and potential synthesis/hardware mismatches. See `bugs_and_fixes.md` Bug #2 for full details.
