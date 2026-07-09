# Vivado 2025.2 / Vitis 2025.2 — Differences from Tutorial

The tutorial was recorded on Vivado 2017.4 / Xilinx SDK. This document lists every confirmed difference encountered when following the tutorial on Vivado 2025.2.1 / Vitis 2025.2, and what to do about each one.

---

## 1. Xilinx SDK Replaced by Vitis

**Tutorial:** Uses Xilinx SDK.  
**2025:** SDK is no longer supported. Use **Vitis 2025.2**.

**Workflow change — Vitis requires a Platform step that SDK did not:**

| SDK (tutorial) | Vitis 2025 |
|----------------|------------|
| Create project | Create Platform (connect to `.xsa`) |
| — | Build Platform |
| Create application | Create Empty Application (connect to platform) |
| Add source files | Add source files to `src/` |
| Build and run | Build and run |

The Platform step exists because the application links against platform-generated headers (`xparameters.h`, BSP libraries) that only exist after the platform is built.

---

## 2. `slv_reg_wren` Not Auto-Generated in AXI-Lite Template

**Tutorial:** Auto-generated AXI-Lite slave template includes `slv_reg_wren` and a complete write state machine.  
**2025:** Neither is auto-generated. The template uses `S_AXI_WVALID` in some places instead.

**What to add manually:**

```verilog
// Add to wire declarations
wire slv_reg_wren;

// Add the assignment
assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;
```

Also add the full Waddr/Wdata write state machine. See the tutorial at approximately 15:34, or `docs/05_oled_part4_axi_software.md` Step 5.

---

## 3. External Block Design Ports Created With `_0` Suffix

**Tutorial:** External ports are named exactly as the underlying signal (e.g., `oled_spi_clk`).  
**2025:** Ports are auto-named with a `_0` suffix (e.g., `oled_spi_clk_0`). This breaks the constraints file, which expects the original names.

**Fix:**
1. Click each external port in the block design (turns orange when selected).
2. **External Port Properties → Name** — remove the `_0` suffix.
3. Press Enter. Repeat for all OLED ports.
4. Save the block design before re-running synthesis.

---

## 4. `[Common 17-180] Spawn Failed: The Operation Completed Successfully`

**Tutorial:** No such message.  
**2025:** This error appears during IP packaging, synthesis launch, and Generate Output Products. It is a known Vivado 2025 Windows process-spawning bug. **The message text is self-contradictory and misleading** — it does not mean your operation actually failed.

**What to do:**

- **During synthesis launch:** Use the Tcl console instead of the GUI button:
  ```tcl
  reset_run synth_1
  launch_runs synth_1 -jobs 2
  wait_on_run synth_1
  ```
- **During Generate Output Products:** Click OK, then re-run Generate Output Products standalone. If it completes the second time without an error dialog, the files were generated correctly.
- **Do not assume your source edits propagated** if Generate Output Products shows this error — verify the `.gen` copy of your file before trusting the build. Use the Tcl console to find the exact path:
  ```tcl
  get_files -all *S00_AXI*
  ```

---

## 5. Custom IP Drivers Cannot Be Attached via TCL in Vitis 2025.x

**Tutorial:** Driver `.h`/`.c` files are attached to the IP package via the IP Packager's TCL driver mechanism.  
**2025:** This mechanism does not work in Vitis 2025.x:
- `main.c` cannot find the driver headers when attached via TCL.
- Editing the `.tcl` file to fix it causes bitstream generation to fail.

**Working solution:**
1. Build the platform first.
2. Locate the driver `.h` and `.c` files in the IP's `drivers/` folder or in the generated platform BSP.
3. Copy them directly into the `src/` folder of your Vitis application, alongside `main.c`.
4. The compiler finds them as local source files. No TCL involvement.

---

## 6. Board Initialization Must Be Set to FSBL for Custom IP

**Tutorial:** May not mention this explicitly.  
**2025:** The default board initialization mode (TCL) does not work with custom IP and throws:
```
Vitis error: "invalid command name 'ps7_init'"
```

**Fix:** Before running any application that uses custom IP:
1. Right-click application → Run/Debug Configurations → (or click the gear icon).
2. Find **Board Initialization**.
3. Change to **FSBL**.

This applies to every custom IP project — the GPIO example in Video 7 and the OLED AXI IP in Video 9.

---

## 7. Block Design Auto-Connection Layout Looks Different

**Tutorial:** Block design auto-connection produces a specific visual layout.  
**2025:** The Vivado 2025 Connection Automation result has a different visual layout — more blocks may be auto-inserted, and the arrangement differs. The underlying connections are functionally equivalent. Accept the auto-connection result and proceed.

To clean up the diagram after running Connection Automation:
```tcl
regenerate_bd_layout -routing
```

---

## 8. Methodology Warnings: TIMING-17 "Not Reached by a Timing Clock"

**Tutorial:** Not documented.  
**2025:** After implementation, the Methodology tab shows 17 TIMING-17 Critical Warnings for registers inside `spiController` — "clock pin is not reached by a timing clock."

**Cause:** The `S00_AXI_CLK` clock interface on the custom IP lacks the `FREQ_HZ` parameter in its `component.xml` metadata. Without it, Vivado's static timing analysis cannot trace the clock object from `FCLK_CLK0` through the IP boundary into the internal registers during out-of-context synthesis.

**Impact:** The design functions correctly. Vivado simply cannot perform full timing verification on the SPI controller's internal registers. At 100 MHz with this design's timing margins (WNS = 2.778 ns post-implementation), this is not a functional risk.

**Status:** These 17 warnings were investigated but not resolved. Two related IP packaging warnings exist alongside them:
- `[IP_Flow 19-11770] Clock interface 'S00_AXI_CLK' has no FREQ_HZ parameter`
- `[IP_Flow 19-4751] Bus Interface 'oled_spi_clk': FREQ_HZ bus parameter is missing for output clock interface`

The `FREQ_HZ` parameter for `S00_AXI_CLK` is not accessible via the IP Packager GUI in Vivado 2025 — it does not appear in the Parameters tab of the Edit Interface dialog. A Tcl-based approach may be possible but has not been confirmed to resolve the downstream TIMING-17 warnings. The root cause is likely a missing OOC (out-of-context) clock constraint XDC file for the IP, which is a separate issue from the metadata parameter alone. This remains an open known limitation of this design.

---

## 9. TIMING-18 Warnings: Missing Output Delay on OLED Ports

**Tutorial:** Not documented.  
**2025:** 5 warnings that output delay constraints are missing on OLED output ports (`oled_dc_n`, `oled_reset_n`, `oled_spi_clk`, `oled_vbat`, `oled_vdd`).

**Cause:** Vivado attempts to enforce clock-edge timing on these output ports because it cannot determine they are unrelated to the system clock. Without being told otherwise, Vivado's timing-driven router treats them as synchronous outputs that must meet a clock constraint.

**Impact:** These warnings are cosmetic — the design functions correctly regardless of whether the OLED is standalone or combined with other components. The `set_false_path` constraint eliminates the warnings and reduces implementation time but is not required for correct operation.

**Fix:** Add `set_false_path` to the constraints file. This tells Vivado these signals have no timing relationship with any clock, which is correct — the OLED is a slow SPI peripheral, not a synchronous endpoint:

```xdc
set_false_path -to [get_ports {oled_dc_n oled_reset_n oled_spi_clk oled_vbat oled_vdd}]
```

This eliminates all 5 TIMING-18 warnings and reduces implementation time. Add this line even if you are not currently combining the OLED with other components — it is the correct constraint for these signals regardless.

> **Note:** If the OLED fails to initialize in a combined project, the root cause is more likely the `oledControl.v` synthesis pruning bugs — see `bugs_and_fixes.md` Bugs #6–#8. The `set_false_path` constraint addresses warnings only, not initialization failures.

---

## 10. Vitis Unified IDE (VS Code-based) Instead of Eclipse

**Tutorial:** Vitis Classic (Eclipse-based).  
**2025:** Vitis Unified IDE is VS Code-based. The UI layout is substantially different.

**Key navigation differences:**

| Task | Eclipse (tutorial) | VS Code (Vitis 2025) |
|------|-------------------|---------------------|
| Watch expressions | Window → Show View → Expressions | View → Debug (`Ctrl+Shift+D`) → Watch section |
| GDB commands | Console tab | Debug Console (`Ctrl+Shift+Y`) |
| Memory view | Window → Show View → Memory | View → Memory Inspector |

**Most reliable register read during debugging:** Use the Debug Console with GDB's memory-examine command:
```
x/4xw 0x43C00000
```
This prints four 32-bit words starting at the given address — all four AXI registers in one unambiguous output. This bypasses display-layer formatting issues that can make the Memory Inspector hard to interpret.

When the debugger's output is ambiguous, fall back to `xil_printf` in your C code — it is always authoritative since the CPU itself is doing the read.

---

## 11. OLED Constraints Must Use `LVCMOS33`, Not `LVCMOS18`

**Tutorial:** Uses `LVCMOS18` for all OLED port voltage standards.  
**Impact when combining with other components:** Using `LVCMOS18` works for a standalone OLED-only project but causes a voltage conflict error as soon as any other component is added that shares bank 13.

**Cause:** All OLED pins on the ZedBoard are on **I/O bank 13**, which is a 3.3V bank. The ZedBoard's Pmod connectors are also on bank 13 and also operate at 3.3V. A single I/O bank can only operate at one voltage — if any pin in the bank is declared `LVCMOS18` (1.8V) while the bank supplies 3.3V, or while another pin in the same bank is declared `LVCMOS33`, Vivado throws a bank voltage conflict error and the build fails.

**Fix:** Use `LVCMOS33` for all OLED port `IOSTANDARD` constraints:

```xdc
set_property IOSTANDARD LVCMOS33 [get_ports oled_dc_n]
set_property IOSTANDARD LVCMOS33 [get_ports oled_reset_n]
set_property IOSTANDARD LVCMOS33 [get_ports oled_spi_clk]
set_property IOSTANDARD LVCMOS33 [get_ports oled_spi_data]
set_property IOSTANDARD LVCMOS33 [get_ports oled_vbat]
set_property IOSTANDARD LVCMOS33 [get_ports oled_vdd]
```

Use `LVCMOS33` even in a standalone OLED project — it reflects the actual hardware voltage and prevents the error from appearing the moment you expand the design.
