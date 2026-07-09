# Video 9 — OLED Part 4: AXI-Lite IP and Software Driver

**Video:** [OLED Part 4](https://www.youtube.com/watch?v=c0w33XQDC6M&list=PLXHMvqUANAFOviU0J8HSp0E91lLJInzX1&index=16)  
**Vivado 2025 differences:** Significant — all documented below.

This video combines everything from the series: the hardware OLED controller (Parts 1–3) is wrapped in a custom AXI-Lite IP (Videos 6–8), and software running on the Zynq PS writes characters to the display through memory-mapped registers.

---

## Prerequisites

- Working Part 3 project (`oledControl` displaying `Hello World` via pure hardware) — verify this still works before starting Part 4.
- Familiarity with custom IP creation (Video 7) and Vitis driver pattern (Video 8).

---

## Project Setup

### Step 1: Copy the Part 3 Project

Copy your working Part 3 Vivado project and rename it (e.g., `oledPart4`). This preserves the working hardware reference while you build the AXI version.

### Step 2: Create the IP Repository Folder

Create the IP folder **before** creating the IP in Vivado:

```
zedboard/ip_repo/oledControlp4/
```

> **Critical:** Vivado bakes the IP path into its metadata at creation time. If you create the IP in the wrong folder and move it afterward, the IP becomes unusable. If this happens, delete it and recreate it in the correct location.

---

## Building the AXI-Lite IP

> **Follow the video for the general Verilog structure.** The steps below do not reproduce the full Verilog from the tutorial — watch the video and write the code alongside it. What is documented here are the **specific changes and additions required for Vivado 2025.2.1** that differ from what the tutorial shows, plus fixes to bugs found during testing. If the tutorial and these notes say different things about the same piece of code, follow these notes.

### Vivado 2025.2.1 — Verilog Changes Required

The following changes are specific to Vivado 2025.2.1 and are **not shown in the tutorial video**. Everything else in the Verilog — port additions, module instantiations, `top.v` content, the overall structure — follows the video directly.

| File | What to Add/Change | Why |
|------|-------------------|-----|
| `oledControlp4_slave_lite_v2_0_S00_AXI.v` | Declare `wire sendDone` and `wire slv_reg_wren` explicitly | Vivado 2025 does not auto-generate these — relying on implicit net rules is a correctness risk |
| `oledControlp4_slave_lite_v2_0_S00_AXI.v` | Add the `slv_reg_wren` assign statement and the full Waddr/Wdata write state machine | Not auto-generated in Vivado 2025 — the template omits both entirely |
| `oledControlp4_slave_lite_v2_0_S00_AXI.v` | In the `slv_reg0` and `slv_reg1` dedicated `always` blocks, use `(S_AXI_AWVALID ? S_AXI_AWADDR : axi_awaddr)` for address matching — not `axi_awaddr` alone | Critical: using only `axi_awaddr` causes a one-cycle timing race that silently drops writes to these registers — see `bugs_and_fixes.md` Bug #5 |
| `oledControlp4_slave_lite_v2_0_S00_AXI.v` | In the `top oledTop(...)` instantiation at the bottom, use `.sendData(slv_reg2[7:0])` not `.sendData(slv_reg2)` | `slv_reg2` is 32-bit; `top.v`'s `sendData` port is 8-bit — explicit slicing prevents a width mismatch synthesis warning and makes the truncation intent clear |

---

### Step 3: Create the Custom IP

1. **Tools → Create and Package New IP**
2. Choose: **Create a new AXI4 peripheral**
3. Configure:
   - Name: `oledControlp4`
   - IP location: `<your_path>/zedboard/ip_repo/oledControlp4`
   - Interface: AXI4-Lite Slave
   - Number of registers: 4
4. Choose **Edit IP** when prompted — this opens the IP project.
5. Add the `.v` files from OLED Part 3.

> **Before adding `oledControl.v`:** This file requires three fixes not shown in the tutorial — see `bugs_and_fixes.md` Bugs #6, #7, and #8. The fixes are three lines in the main `always @(posedge clock)` block. Without them the OLED works standalone but fails to initialize once combined with any other component (such as a Pmod TMP2 over IIC).

After creation, verify in File Explorer that the IP is at the correct path before proceeding.

### Step 4: Add OLED Output Ports

In `oledControlp4_slave_lite_v2_0_S00_AXI.v`, add the OLED ports to the module port list:

```verilog
// Users to add ports here
output oled_spi_clk,
output oled_spi_data,
output oled_vdd,
output oled_vbat,
output oled_reset_n,
output oled_dc_n,
// User ports ends
```

Do the same in the top-level wrapper `oledControlp4.v`.

### Step 5: Add Missing Vivado 2025 Signals

> **Vivado 2025 difference:** The auto-generated AXI-Lite slave template does not include `slv_reg_wren` or the write state machine. Both must be added manually.

**5a. Declare internal wires** (add after the `slv_reg` declarations):

```verilog
wire sendDone;
wire slv_reg_wren;
```

**5b. Add the write-enable assignment:**

```verilog
assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;
```

**5c. Add the write state machine** (Waddr/Wdata states). See the tutorial video at approximately 15:34, or the source file in this repository.

> **Spelling warning from the tutorial:** Watch for typos in signal names (e.g., `S_AXI_ARESETN` vs `S_AXL_ARESETN`). A single wrong character will cause a silent connection failure.

### Step 6: Register Map Design

The four AXI registers have these roles:

| Register | Offset | Direction | Purpose |
|----------|--------|-----------|---------|
| `slv_reg0` | `+0x0` | PS writes, HW clears | Control — bit 0 = `sendDataValid` |
| `slv_reg1` | `+0x4` | HW sets, PS clears | Status — nonzero = transfer complete |
| `slv_reg2` | `+0x8` | PS writes | Data — ASCII character byte |
| `slv_reg3` | `+0xC` | — | Reserved |

### Step 7: Implement Register Logic

> **Read `docs/bugs_and_fixes.md` Bug #5 before writing this code.** The address-matching condition is the most critical detail in the entire project. Using the wrong form here causes a silent failure that is very difficult to diagnose without hardware debugging tools.

**`slv_reg0` — Control register (PS writes to trigger, hardware clears on completion):**

```verilog
always @(posedge S_AXI_ACLK)
begin
  if (S_AXI_ARESETN == 1'b0)
      slv_reg0 <= 0;
  else
  begin
     if(sendDone)
         slv_reg0 <= 0;
     else if(slv_reg_wren && ((S_AXI_AWVALID) ? S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] : axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]) == 0)
         slv_reg0 <= S_AXI_WDATA;
  end
end
```

**`slv_reg1` — Status register (hardware sets on completion, PS clears after reading):**

```verilog
always @(posedge S_AXI_ACLK)
begin
  if (S_AXI_ARESETN == 1'b0)
      slv_reg1 <= 0;
  else
  begin
     if(sendDone)
         slv_reg1 <= 1;
     else if(slv_reg_wren && ((S_AXI_AWVALID) ? S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] : axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]) == 1)
         slv_reg1 <= S_AXI_WDATA;
  end
end
```

**Remove `slv_reg0`/`slv_reg1` from the main case block.** Delete the `2'h0` and `2'h1` cases — those registers now have their own dedicated `always` blocks.

### Step 8: Instantiate Hardware Modules (User Logic)

At the bottom of `_S00_AXI.v`, replace `// Add user logic here` with:

```verilog
top oledTop(
    .clock(S_AXI_ACLK),
    .reset(!S_AXI_ARESETN),
    .oled_spi_clk(oled_spi_clk),
    .oled_spi_data(oled_spi_data),
    .oled_vdd(oled_vdd),
    .oled_vbat(oled_vbat),
    .oled_reset_n(oled_reset_n),
    .oled_dc_n(oled_dc_n),
    .sendData(slv_reg2[7:0]),
    .sendDataValid(slv_reg0[0]),
    .sendDone(sendDone)
);
```

### Step 9: `top.v` — Passthrough Module

`top.v` is a thin passthrough that connects the AXI IP ports to `oledControl`:

```verilog
module top(
    input clock,
    input reset,
    output oled_spi_clk,
    output oled_spi_data,
    output oled_vdd,
    output oled_vbat,
    output oled_reset_n,
    output oled_dc_n,
    input [7:0] sendData,
    input sendDataValid,
    output sendDone
);
oledControl OC(
    .clock(clock),
    .reset(reset),
    .oled_spi_clk(oled_spi_clk),
    .oled_spi_data(oled_spi_data),
    .oled_vdd(oled_vdd),
    .oled_vbat(oled_vbat),
    .oled_reset_n(oled_reset_n),
    .oled_dc_n(oled_dc_n),
    .sendData(sendData),
    .sendDataValid(sendDataValid),
    .sendDone(sendDone)
);
endmodule
```

### Step 10: Fix `spiController.v`

Change the blocking assignment in the `DONE` state:

```verilog
CE = 0;    // WRONG
CE <= 0;   // CORRECT
```

---

## Packaging the IP

### Step 11: Package the IP

In the IP Packager, go to **Review and Package → Re-Package IP**.

**Expected messages (all safe to proceed):**

| Message | Meaning |
|---------|---------|
| `The Product Guide file is missing` | No PDF documentation required — harmless |
| `Clock interface 'S00_AXI_CLK' has no FREQ_HZ parameter` | Metadata only — does not affect function |
| `Spawn failed: The operation completed successfully` | Known Vivado 2025 bug — harmless |
| `check_integrity: Integrity check passed` | ✅ This is the important one — IP is valid |

---

## Block Design (oledControllerTestp4 Project)

### Step 12: Create the Vivado Project

Create a new RTL project at `zedboard/oledControllerTestp4/vivado`.

Add the IP repository: **Settings → IP → Repository → Add** → point to `zedboard/ip_repo/oledControlp4`.

### Step 13: Block Design

Add IP blocks:
- ZYNQ7 Processing System
- `oledControlp4` (your custom IP)
- AXI SmartConnect (added automatically by Connection Automation)
- Processor System Reset (added automatically by Connection Automation)

Run **Connection Automation** and accept defaults. Run `regenerate_bd_layout -routing` in the Tcl console to clean up the diagram.

### Step 14: Make OLED Ports External

Right-click each OLED port on the `oledControlp4` block → **Make External**.

> **Vivado 2025 difference:** External ports are created with a `_0` suffix (e.g., `oled_spi_clk_0`). The constraints file requires names without the suffix.

**Fix:**
1. Click each external port (it turns orange).
2. In **External Port Properties → Name**, remove the `_0` suffix.
3. Press Enter. Repeat for all OLED ports.
4. Save the block design.

### Step 15: Constraints File

Copy `oledControl.xdc` from the Part 3 project. Make three changes: remove the `clock` and `reset` lines (now handled by the PS), change all `LVCMOS18` to `LVCMOS33`, and add the `set_false_path` line at the end:

```xdc
set_property PACKAGE_PIN U12 [get_ports oled_vdd]
set_property PACKAGE_PIN U11 [get_ports oled_vbat]
set_property PACKAGE_PIN AA12 [get_ports oled_spi_data]
set_property PACKAGE_PIN AB12 [get_ports oled_spi_clk]
set_property PACKAGE_PIN U9 [get_ports oled_reset_n]
set_property PACKAGE_PIN U10 [get_ports oled_dc_n]
set_property IOSTANDARD LVCMOS33 [get_ports oled_dc_n]
set_property IOSTANDARD LVCMOS33 [get_ports oled_reset_n]
set_property IOSTANDARD LVCMOS33 [get_ports oled_spi_clk]
set_property IOSTANDARD LVCMOS33 [get_ports oled_spi_data]
set_property IOSTANDARD LVCMOS33 [get_ports oled_vbat]
set_property IOSTANDARD LVCMOS33 [get_ports oled_vdd]
set_false_path -to [get_ports {oled_dc_n oled_reset_n oled_spi_clk oled_vbat oled_vdd}]
```

> **Why `LVCMOS33` not `LVCMOS18`:** All OLED pins on the ZedBoard are on **bank 13**, which operates at 3.3V. Bank 13 also serves the ZedBoard's Pmod connectors, which are 3.3V. Declaring `LVCMOS18` on a 3.3V bank causes a voltage conflict error in Vivado — especially when adding any other component on bank 13 (such as a sensor on a Pmod), since a bank cannot simultaneously supply 1.8V and 3.3V. The OLED works standalone with `LVCMOS18` in a simple single-component project, but will fail as soon as anything else shares the bank.

> **Why `set_false_path`:** The custom OLED IP produces 17 TIMING-17 Critical Warnings for internal registers not reached by a timing clock (a known accepted limitation — see `vivado_2025_differences.md`). Separately, Vivado also generates 5 TIMING-18 warnings where it attempts to enforce clock-edge timing on the OLED output ports themselves. `set_false_path` tells Vivado these signals have no timing relationship with any clock — which is correct, since the OLED is a slow SPI peripheral, not a synchronous endpoint. This eliminates the 5 TIMING-18 warnings. More importantly, **without this line the OLED will stop working if any other component is added to the same project** — Vivado's timing-driven router makes conflicting routing decisions for those output paths when it believes they must meet a clock constraint.

---

## Synthesis, Implementation, Bitstream

### Step 16: Build

1. Run Synthesis.
2. Run Implementation — verify no critical warnings about unassigned pins.
3. Generate Bitstream.
4. **File → Export → Export Hardware** — check **Include Bitstream**.

> **If synthesis fails with `[Common 17-180] Spawn failed`**, use the Tcl console:
> ```tcl
> reset_run synth_1
> launch_runs synth_1 -jobs 2
> wait_on_run synth_1
> ```

> **After any IP source edit**, verify the change propagated to the `.gen` copy before trusting a rebuild. In the Tcl console: `get_files -all *S00_AXI*` to find the exact path Vivado is using, then open that file and confirm your edit is present.

---

## Vitis Software Project

### Step 17: Vitis Setup

1. Create Platform connected to the exported `.xsa`.
2. Build Platform.
3. Create Empty Application linked to the platform.
4. Copy `oled.h`, `oled.c`, `main.c` into the application's `src/` folder.
5. In `main.c`, use the correct base address macro — check `xparameters.h` in the BSP if unsure:
   ```c
   initOled(&myOled, XPAR_OLEDCONTROLP4_0_BASEADDR);
   ```
6. **Run/Debug Settings → Board Initialization → FSBL** (required for custom IP).
7. Build and run.

---

## Software Driver

### `oled.h`

```c
#ifndef SRC_OLED_H_
#define SRC_OLED_H_

#include <xil_types.h>

typedef struct oledControl {
    u32 baseAddress;
} oledControl;

int initOled(oledControl *myOled, u32 baseAddress);
void writeCharOled(oledControl *myOled, char myChar);
void printOled(oledControl *myOled, char *myString);
void clearOled(oledControl *myOled);

#endif /* SRC_OLED_H_ */
```

### `oled.c`

```c
#include "oled.h"
#include <xil_io.h>

int initOled(oledControl *myOled, u32 baseAddress) {
    myOled->baseAddress = baseAddress;
    return 0;
}

void writeCharOled(oledControl *myOled, char myChar) {
    u32 status = 0;
    Xil_Out32(myOled->baseAddress + 8, myChar); // Write char to slv_reg2 (data)
    Xil_Out32(myOled->baseAddress, 0x1);         // Set bit 0 of slv_reg0 (sendDataValid)
    while(!status) {
        // Uncomment the lines below to debug register values while polling:
        // xil_printf("reg0=%08x reg1=%08x reg2=%08x reg3=%08x\n",
        // Xil_In32(myOled->baseAddress+0),
        // Xil_In32(myOled->baseAddress+4),
        // Xil_In32(myOled->baseAddress+8),
        // Xil_In32(myOled->baseAddress+12));
        status = Xil_In32(myOled->baseAddress + 4); // Poll slv_reg1 (status/done)
    }
    Xil_Out32(myOled->baseAddress + 4, 0x0); // Clear status register
}

void printOled(oledControl *myOled, char *myString) {
    while(*myString != 0) {
        // myOled is a pointer — using a pointer to a pointer
        writeCharOled(myOled, *myString);
        myString++; // Increment to next character in string
    }
}

void clearOled(oledControl *myOled) {
    // 4 pages × 16 characters per page = 64 space characters to blank the full display
    // Each character occupies 8 columns; 128 columns / 8 = 16 characters per page
    u32 i;
    for (i = 0; i < 64; i++) {
        writeCharOled(myOled, ' ');
    }
}
```

> **Debugging tip:** The commented-out `xil_printf` block inside `writeCharOled` prints all four AXI register values on every poll cycle. Uncomment it when diagnosing a hang in the polling loop — it will show exactly what `slv_reg0`/`slv_reg1` contain, which is often enough to identify the root cause without needing the ILA. Remove or re-comment before final use to avoid UART output slowing down the display.

### `main.c`

```c
#include "oled.h"
#include <stdio.h>
#include <xparameters.h>
#include "sleep.h"

int main() {
    char *myString = "Hello World";
    oledControl myOled;
    initOled(&myOled, XPAR_OLEDCONTROLP4_0_BASEADDR);
    clearOled(&myOled);       // Clear any leftover content before writing
    printOled(&myOled, myString);

    // Example: display a counter (0-99), updating every second
    // char buffer[4];   // enough for "99\0"
    // for (int i = 0; i < 100; i++) {
    //     sprintf(buffer, "%d", i);
    //     printOled(&myOled, buffer);
    //     sleep(1);
    // }

    return 0;
}
```

---

## How the Handshake Works (End to End)

For each character `writeCharOled` sends:

1. PS writes the ASCII byte to `slv_reg2` (offset `+8`).
2. PS writes `0x1` to `slv_reg0` (offset `+0`) — sets `sendDataValid` high.
3. Hardware FSM (`oledControl`) sees `sendDataValid = 1` while in `DONE` state → transitions to `SEND_DATA`.
4. FSM looks up the character's 8-byte bitmap in `charROM`, sends all 8 bytes over SPI.
5. FSM asserts `sendDone` for one clock cycle.
6. AXI slave logic sees `sendDone`:
   - Clears `slv_reg0` → `sendDataValid` drops to 0.
   - Sets `slv_reg1` to 1 → signals software that transfer is complete.
7. PS polling loop (`while(!status)`) sees nonzero `slv_reg1` → exits.
8. PS clears `slv_reg1` → ready for next character.

---

## Known Behavior (Not a Bug)

Characters are written left to right across columns. After column 128, the FSM wraps to the next page. After all 4 pages are filled, it wraps back to the beginning and overwrites existing content.

**Recommended practice:** Call a screen-clear function before writing new content to avoid leftover characters from previous writes or power-on state.

---

## Potential Improvements and Future Changes

These are known limitations and ideas for extending the design beyond what the tutorial implements.

**1. Control over page and column addressing**  
Currently the hardware FSM manages page and column position internally — software has no way to specify where on the screen a character is written. A useful extension would be to expose page and column as writable AXI registers, allowing software to position the cursor before sending characters. This would enable multi-line layouts, overwriting specific regions, and more structured display formatting.

**2. Move initialization sequence to software**  
The current design runs the full SSD1306 initialization sequence in hardware (inside `oledControl.v`) automatically on power-up. An alternative architecture would keep only the SPI communication engine in hardware (PL) and move the initialization command sequence into software (PS). This would make the initialization steps more readable and configurable, and would make it easier to experiment with different SSD1306 display settings without modifying or rebuilding the Verilog.

**3. OLED power-off command for display longevity**  
The ZedBoard demo project includes a power-off command sequence for the OLED that should be sent before cutting power to the board. OLED displays have a finite lifespan that is shortened by leaving them on continuously — properly powering down the display when it is not in use extends its lifetime. A `powerOffOled()` driver function that sends the appropriate SSD1306 shutdown commands would be a practical addition to the driver.

