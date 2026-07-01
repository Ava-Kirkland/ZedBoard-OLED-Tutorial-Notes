# Vitis Troubleshooting Guide

Quick-reference for errors and unexpected behavior encountered in **Vitis 2025.2** while following this tutorial series. Each entry is structured as: **symptom → cause → fix**.

For Verilog/hardware bugs, see [`bugs_and_fixes.md`](bugs_and_fixes.md).  
For Vivado-specific issues, see [`vivado_2025_differences.md`](vivado_2025_differences.md).

---

## Table of Contents

1. [Application Run/Debug Errors](#1-applicationrundebug-errors)
   - [`invalid command name 'ps7_init'`](#11-invalid-command-name-ps7_init)
   - [`No connection established / ECONNREFUSED`](#12-no-connection-established--econnrefused)
   - [Application runs but OLED shows gibberish](#13-application-runs-but-oled-shows-gibberish)
   - [Application hangs in `while(!status)` loop](#14-application-hangs-in-whilestatus-loop)
2. [Build Errors](#2-build-errors)
   - [Undeclared identifier: `XPAR_..._BASEADDR`](#21-undeclared-identifier-xpar__baseaddr)
   - [Driver header not found (`#include "oled.h"` fails)](#22-driver-header-not-found-include-oledh-fails)
   - [Platform build fails after editing IP source](#23-platform-build-fails-after-editing-ip-source)
3. [Platform and Hardware Spec Issues](#3-platform-and-hardware-spec-issues)
   - [Platform still references old IP after changes](#31-platform-still-references-old-ip-after-changes)
   - [Hardware spec update not picking up new bitstream](#32-hardware-spec-update-not-picking-up-new-bitstream)
4. [Debugging in Vitis Unified IDE](#4-debugging-in-vitis-unified-ide)
   - [How to read raw register values while paused](#41-how-to-read-raw-register-values-while-paused)
   - [Memory Inspector output is ambiguous](#42-memory-inspector-output-is-ambiguous)
   - [Watch expressions not updating while running](#43-watch-expressions-not-updating-while-running)

---

## 1. Application Run/Debug Errors

### 1.1 `invalid command name 'ps7_init'`

**Full error:**
```
Vitis: "invalid command name 'ps7_init'"
```

**Cause:** Vitis is using the default **TCL** board initialization mode, which does not work with custom IP. TCL initialization calls `ps7_init` as a script-based setup routine; this command is not available in the Vitis 2025.x environment when custom IP is present.

**Fix:** Change the board initialization mode to **FSBL** before running:

1. Right-click your application in the Vitis Explorer → **Run As → Run Configurations** (or click the gear icon next to the Run button).
2. Find the **Board Initialization** setting.
3. Change it from the default to **FSBL**.
4. Apply and run again.

> This setting must be changed for every new application that uses custom IP. It does not carry over automatically.

---

### 1.2 `No connection established / ECONNREFUSED`

**Full error:**
```
Error: No connection established. Last error: connect ECONNREFUSED ::1:53597
```

**Cause:** Vitis cannot reach the background hardware server (`hw_server` / TCF agent) it needs to communicate with the board or perform device queries. The server either crashed, was never started, is still initializing, or a stale instance from a previous session is occupying the port.

**Fix — try in order:**

1. **Close Vitis entirely.** Open Task Manager and check for orphaned `hw_server.exe` or `vitis` background processes — kill any that remain. Reopen Vitis and retry.

2. **If multiple Vivado/Vitis versions are installed**, a `hw_server.exe` from a different version may still be bound to the port. Kill all instances via Task Manager before relaunching.

3. **Check firewall/antivirus.** Some security software intermittently blocks local loopback connections. Temporarily check whether Windows Defender or another AV is flagging Vitis's server spawn.

4. **Reboot.** After a long session with multiple tool resets and stale processes (common when iterating on IP), a clean reboot clears zombie background processes reliably.

5. **Confirm the `.xsa` is not locked.** If Vivado still has a file handle open on the `.xsa` (e.g., the Export Hardware dialog did not fully close), Vitis can fail when trying to read it. Close Vivado's export dialogs fully before switching to Vitis.

---

### 1.3 Application Runs but OLED Shows Gibberish

**Symptom:** The OLED powers on and displays random pixel patterns or incorrect characters. The application does not hang — it runs to completion but the output is wrong.

**Possible causes and fixes:**

**A — Software writing bytes faster than hardware can process them (most likely):**  
The status register (`slv_reg1`) is not being read correctly, so the polling loop exits immediately instead of waiting for hardware to finish. See [1.4](#14-application-hangs-in-whilestatus-loop) for register verification steps — the same diagnostic applies here, except the register reads nonzero when it should not.

Check your `slv_reg1` `always` block: confirm the address check uses `== 1`, not `== 0`. See `bugs_and_fixes.md` Bug #4.

**B — Stale bitstream on the FPGA:**  
The FPGA may be running an older bitstream that does not include your latest Verilog changes. Verify the correct bitstream was programmed:
- In Vitis debug mode, check that the platform was rebuilt after the last `Export Hardware` from Vivado.
- Right-click platform → **Update Hardware Specification** → point to the latest `.xsa`.
- Rebuild platform → rebuild application → re-run.

**C — Wrong base address:**  
`main.c` may be using a hardcoded address (`0x43C00000`) from a previous project instead of the auto-generated macro for the current IP. Check `xparameters.h` in the platform BSP for the correct macro name and use that:
```c
// Use the macro, not a hardcoded address
initOled(&myOled, XPAR_OLEDCONTROLP4_0_BASEADDR);
```

**D — OLED not cleared before writing:**  
If a previous run or power cycle left pixel data in the OLED's GDRAM, new characters may overlap existing content. Call a screen-clear function before writing new content.

---

### 1.4 Application Hangs in `while(!status)` Loop

**Symptom:** The application starts, the OLED powers on (may show gibberish from initialization), then the application hangs indefinitely inside the polling loop:
```c
while(!status) {
    status = Xil_In32(myOled->baseAddress + 4);
}
```
The debugger shows execution stuck at this line. `status` never becomes nonzero.

**Cause:** The status register (`slv_reg1`, offset `+4`) never gets set because the hardware FSM never signals `sendDone`. This has two sub-causes:

1. The hardware FSM is stuck in the initialization sequence and never reached the `DONE` state.
2. The FSM reached `DONE` but `sendDataValid` (`slv_reg0[0]`) is not being seen as `1` — so the FSM never transitions to `SEND_DATA`.

**Diagnostic — read all four registers while hung:**

Add this immediately before the `while(!status)` loop in `writeCharOled`:

```c
xil_printf("reg0=%08x reg1=%08x reg2=%08x reg3=%08x\n",
    Xil_In32(myOled->baseAddress + 0),
    Xil_In32(myOled->baseAddress + 4),
    Xil_In32(myOled->baseAddress + 8),
    Xil_In32(myOled->baseAddress + 12));
```

**Interpret the output:**

| `reg0` value | `reg2` value | Meaning |
|-------------|-------------|---------|
| `0x00000001` | Correct char | ✅ Control write landed — bug is in hardware FSM or timing |
| `0x00000000` | Correct char | Control write was dropped — check AXI address decode logic |
| Same as `reg2` | Same | AXI address timing bug — `slv_reg0` captured `reg2`'s data instead |

If `reg0` holds the same value as `reg2` (e.g., both show `0x00000048` for 'H'), you have the stale-address AXI timing bug described in `bugs_and_fixes.md` Bug #5. The fix is to change the address-match condition in the `slv_reg0` `always` block from `axi_awaddr[...]` to `(S_AXI_AWVALID ? S_AXI_AWADDR : axi_awaddr)[...]`.

**If `reg0` shows `0x1` correctly but still hangs:**  
The hardware FSM is not responding to `sendDataValid`. This requires ILA debugging to observe the FSM's internal `state` register. See `docs/02_ila_debugging.md` for ILA setup.

---

## 2. Build Errors

### 2.1 Undeclared Identifier: `XPAR_..._BASEADDR`

**Full error:**
```
error: 'XPAR_OLED_CONTROL_0_BASEADDR' undeclared (first use in this function);
did you mean 'XPAR_OLEDCONTROLP4_0_BASEADDR'?
```

**Cause:** The base address macro name in `main.c` does not match what Vitis generated for your IP. The macro name is derived from the IP name in your block design — if you renamed the IP or used a different name than the tutorial, the macro will be different.

**Fix:** 
1. Open `xparameters.h` in your platform's BSP (navigate: platform → `ps7_cortexa9_0` → `standalone_domain` → BSP → `include` → `xparameters.h`).
2. Search for `BASEADDR` to find the correct macro name for your IP.
3. Update `main.c` to use the correct macro.

---

### 2.2 Driver Header Not Found (`#include "oled.h"` fails)

**Full error:**
```
fatal error: oled.h: No such file or directory
```

**Cause:** In Vitis 2025.x, driver files attached to the IP package via the TCL-based IP packager mechanism are not correctly picked up by the application build system. This is a known Vitis 2025.x issue.

**Fix (temporary workaround):**
1. Locate `oled.h` and `oled.c` — they are in the IP's `drivers/` folder inside your IP repo, or in the generated platform BSP under the IP's driver directory.
2. Copy both files directly into the `src/` folder of your Vitis application, alongside `main.c`.
3. Rebuild the application.

> Note: You should still add the driver files to the IP package (correct long-term practice). This copy-to-`src/` step is a workaround for the 2025.x TCL loading issue, not a replacement for proper IP packaging.

---

### 2.3 Platform Build Fails After Editing IP Source

**Symptom:** After editing Verilog source in the IP, the platform rebuild in Vitis fails or the application behaves as if the old IP code is still running.

**Cause:** Vitis's platform is built from the `.xsa` file, which is a snapshot of the hardware at the time of export. Editing the Verilog source does not automatically update the platform — the full Vivado build pipeline must run first.

**Fix — required steps after any IP source edit:**

```
Edit IP source (.v file in ip_repo)
    ↓
Generate Output Products (in Vivado — right-click IP in Sources panel)
    ↓
Verify edit propagated to .gen copy (get_files -all *S00_AXI* in Tcl console)
    ↓
Reset and re-run Synthesis
    ↓
Re-run Implementation
    ↓
Generate Bitstream
    ↓
File → Export → Export Hardware (include bitstream) — overwrite existing .xsa
    ↓
Vitis: right-click Platform → Update Hardware Specification → select new .xsa
    ↓
Rebuild Platform
    ↓
Rebuild Application
    ↓
Run/Debug
```

Skipping any step in this chain risks running a stale bitstream on the FPGA while your C code expects the updated register behavior — producing symptoms that are difficult to diagnose.

---

## 3. Platform and Hardware Spec Issues

### 3.1 Platform Still References Old IP After Changes

**Symptom:** After changing the IP and exporting a new `.xsa`, the platform still reflects the old hardware. `xparameters.h` shows old base addresses or missing IP entries.

**Fix:**
1. In Vitis Explorer, right-click your platform → **Update Hardware Specification**.
2. In the dialog, browse to and select the newly exported `.xsa` file.
3. Click OK — Vitis will re-read the hardware description.
4. **Rebuild the platform** (right-click platform → Build) — this regenerates the BSP headers including `xparameters.h`.
5. **Rebuild the application** — it must relink against the updated platform libraries.

Do not skip step 4. Updating the hardware spec alone does not regenerate the BSP headers — you must rebuild the platform for the changes to reach `xparameters.h`.

**If updating the hardware spec does not work — start a fresh Vitis workspace:**

Sometimes Vitis caches stale platform/BSP state that cannot be cleared by an in-place update. The most reliable fix is to rebuild the workspace from scratch:

1. Create a new Vitis workspace folder (e.g., `ws2/` alongside your existing `ws/`).
2. Open Vitis and switch to the new workspace: **File → Switch Workspace**.
3. Create a new Platform connected to the latest `.xsa`.
4. Build the new platform.
5. Create a new Empty Application connected to the new platform.
6. Copy your source files (`main.c`, `oled.c`, `oled.h`, etc.) into the new application's `src/` folder.
7. Set Board Initialization to **FSBL** in Run/Debug Configurations.
8. Build and run.

This is the most reliable recovery path when a platform update produces inconsistent or unexplained behavior — a clean workspace has no cached state to fight against.

---

### 3.2 Hardware Spec Update Not Picking Up New Bitstream

**Symptom:** After updating the hardware spec, the FPGA is still programmed with the old bitstream when the application is launched.

**Cause:** The `.xsa` must be exported from Vivado with **Include Bitstream** checked. If this was unchecked, the `.xsa` contains only the hardware description (for software compilation) but no bitstream (for FPGA programming). Vitis then falls back to whatever bitstream was previously on the device.

**Fix:**
1. In Vivado: **File → Export → Export Hardware**.
2. In the dialog, confirm **Include Bitstream** is checked.
3. Export (overwrite the existing `.xsa`).
4. Repeat the platform update + rebuild steps from [3.1](#31-platform-still-references-old-ip-after-changes).

---

## 4. Debugging in Vitis Unified IDE

### 4.1 How to Read Raw Register Values While Paused

The most reliable way to inspect AXI peripheral registers while the debugger is paused is via the **Debug Console** using GDB's memory-examine command.

1. Start a debug session and pause execution (set a breakpoint or click Suspend).
2. Open the Debug Console: **View → Debug Console** or `Ctrl+Shift+Y`.
3. At the `>` prompt, type:
   ```
   x/4xw 0x43C00000
   ```
   Replace `0x43C00000` with your IP's actual base address.
4. GDB returns four 32-bit hex words in a single unambiguous line:
   ```
   0x43c00000:  0x00000001  0x00000000  0x00000048  0x00000000
   ```
   These are `slv_reg0`, `slv_reg1`, `slv_reg2`, `slv_reg3` in order.

The `x/4xw` command (`examine / 4 words / hex / word-size`) reads directly from memory — it bypasses all display-layer caching and formatting, making it the most trustworthy method.

---

### 4.2 Memory Inspector Output Is Ambiguous

**Symptom:** The Memory Inspector view in Vitis shows a row of hex bytes but it's unclear which bytes correspond to which register, or the byte order seems unexpected.

**Cause:** The Memory Inspector displays raw bytes at increasing addresses. For a 32-bit little-endian system (Zynq ARM is little-endian), the bytes within each 32-bit word are stored LSB-first, which can make the raw byte display look reversed compared to what you'd expect.

**Fix — two alternatives:**

**Option A — Use the GDB Debug Console** (recommended):
```
x/4xw <base_address>
```
GDB reads and displays each 32-bit word correctly assembled, with no byte-order confusion.

**Option B — Use `xil_printf` directly in your C code:**
```c
xil_printf("reg0=%08x reg1=%08x reg2=%08x reg3=%08x\n",
    Xil_In32(myOled->baseAddress + 0),
    Xil_In32(myOled->baseAddress + 4),
    Xil_In32(myOled->baseAddress + 8),
    Xil_In32(myOled->baseAddress + 12));
```
This has the CPU itself read and print the values — completely bypasses the debugger's display layer. Output appears in the Vitis Serial Terminal. This is the most unambiguous diagnostic technique available.

---

### 4.3 Watch Expressions Not Updating While Running

**Symptom:** Watch expressions or Variables panel values do not update while the application is running — they only refresh when execution is paused at a breakpoint.

**Cause:** This is expected behavior in Vitis Unified IDE. The debugger only reads target memory when execution is stopped (at a breakpoint, step point, or manual pause). Live memory watching while running requires a separate tool (ILA for hardware signals, or periodic breakpoints for software variables).

**Fix — choose based on what you need to observe:**

- **Software variable at a specific point:** Set a breakpoint at the relevant line and read the variable when execution pauses there.
- **Register value at a specific point:** Same — breakpoint, then `x/4xw <address>` in Debug Console.
- **Hardware signal over time (state machine state, valid/done pulses):** Use the ILA. See [`02_ila_debugging.md`](02_ila_debugging.md) for setup. The ILA captures internal FPGA signals in real time without stopping the CPU.
- **Periodic software value logging:** Add `xil_printf` calls at the points of interest and watch the Serial Terminal output while the application runs freely.
