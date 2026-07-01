# Bug Log and Root Cause Analysis

Every bug encountered across the full OLED tutorial series (Videos 1–9), with root cause, fix, and lesson learned. Covers both hardware (Verilog) and software (C driver) issues.

---

## Bug #1 — Blocking assignment in state machine (`oledControl.v`, Part 3)

**Symptom:** OLED did not turn on at all. No initialization sequence visible on hardware.

**Root cause:** A single `=` (blocking assignment) was used inside a clocked `always` block instead of `<=` (non-blocking):

```verilog
// WRONG — blocking assignment in a clocked always block
state = NEXT_STATE;

// CORRECT — non-blocking, consistent with all other signals
state <= NEXT_STATE;
```

In Verilog, mixing blocking and non-blocking assignments in a state machine causes signal updates to happen at different points within the same clock cycle, desynchronizing the FSM from the signals it drives. In this case, it prevented the OLED from receiving valid SPI commands during initialization.

**Fix:** Change every `=` inside the state machine's clocked `always` block to `<=`.

**Lesson:** In synthesizable RTL, use `<=` exclusively inside `always @(posedge clk)` blocks. Use `=` only inside combinational `always @(*)` blocks. This is not a style preference — it is a correctness requirement.

---

## Bug #2 — Blocking/non-blocking mix for `CE` in `spiController.v`

**Symptom:** Potential simulation/synthesis mismatch; could corrupt the final SPI bit's clock-gate timing on byte transfers.

**Root cause:** In the `DONE` state of the SPI controller, `CE` (clock enable) was cleared with a blocking assignment while all other signals used non-blocking:

```verilog
always @(negedge clock_10)
begin
    ...
    DONE: begin
        done_send <= 1'b1;
        CE = 0;         // WRONG — blocking, inconsistent
        ...
    end
end
```

`CE = 0` takes effect immediately in the simulation time step, potentially allowing the combinational `spi_clock` mux to glitch before other signals settle. In synthesis, the inferred hardware may not match simulation.

**Fix:**
```verilog
CE <= 0;
```

**Lesson:** Never mix `=` and `<=` for the same signal in the same clocked `always` block, even if the blocking assignment "happens to work" in basic simulations. The divergence between simulation and synthesized hardware will appear in edge cases.

---

## Bug #3 — Missing explicit wire declarations (`_S00_AXI.v`)

**Symptom:** No functional error (Verilog's implicit net rule masked it), but a latent risk under strict synthesis settings.

**Root cause:** Two internal signals were used without declaration:
- `sendDone` — used in `always` blocks and as a port connection
- `slv_reg_wren` — driven by `assign`, used in `always` blocks

Verilog's implicit net rule defaults these to 1-bit wires, which happens to be correct. However, this behavior is tool-dependent.

**Fix:** Add explicit declarations after the `slv_reg` declarations block:

```verilog
wire sendDone;
wire slv_reg_wren;
```

**Lesson:** Always declare every internal signal explicitly. Consider using `` `default_nettype none `` at the top of files to force declaration of all nets — any implicit net then becomes a compile error rather than a silent assumption.

---

## Bug #4 — `slv_reg1` address check used wrong register offset (`_S00_AXI.v`)

**Symptom:** Gibberish displayed on screen. Software polling loop exited immediately after triggering a send, regardless of whether the hardware had actually finished.

**Root cause:** The `slv_reg1` dedicated `always` block was copy-pasted from `slv_reg0` and the address constant was never updated:

```verilog
// WRONG — checks address 0 (slv_reg0), not address 1 (slv_reg1)
else if(slv_reg_wren & axi_awaddr[...] == 0)
    slv_reg1 <= S_AXI_WDATA;
```

Every write to `slv_reg0` (the control register, at address 0) also triggered the `slv_reg1` block, clobbering the status register with the control word. The software polling loop saw a nonzero status immediately — not because hardware was done, but because the control word had just been copied into the status register.

**Fix:** Change `== 0` to `== 1`:

```verilog
else if(slv_reg_wren & axi_awaddr[...] == 1)
    slv_reg1 <= S_AXI_WDATA;
```

**Lesson:** When creating dedicated `always` blocks for individual registers (instead of using the auto-generated case statement), check that the address constant in each block matches that register's actual offset. Copy-paste errors here produce no compile error and only manifest as wrong runtime behavior.

---

## Bug #5 — AXI address-capture timing race: root cause of the main hang

> **This was the primary bug. It is the most important to understand for anyone writing custom AXI-Lite register logic.**

### Symptom

- OLED displayed gibberish on power-up.
- `printOled("Hello World")` hung in `while(!status)` on the first character ('H').
- `slv_reg1` (status register, offset `+4`) read `0x00000000` forever while hung.
- `slv_reg0` (control register, offset `+0`) read `0x00000048` (`'H'`) instead of `0x00000001` after the intended control-register write.
- `slv_reg2` (data register, offset `+8`) correctly read `0x00000048` (`'H'`).

### How It Was Found

After all other fixes were applied and the hang persisted, a diagnostic `xil_printf` was added immediately before the polling loop:

```c
xil_printf("reg0=%08x reg1=%08x reg2=%08x reg3=%08x\n",
    Xil_In32(myOled->baseAddress + 0),
    Xil_In32(myOled->baseAddress + 4),
    Xil_In32(myOled->baseAddress + 8),
    Xil_In32(myOled->baseAddress + 12));
```

Output:
```
reg0=00000048 reg1=00000000 reg2=00000048 reg3=00000000
```

`slv_reg0` held `0x48` (the character data) instead of `0x01` (the intended control value). This pointed to the `slv_reg0` write block capturing data from the wrong transaction.

### Root Cause: How AXI-Lite Writes Work

An AXI-Lite write delivers two pieces of information on potentially separate clock cycles:
- **Address channel:** `S_AXI_AWADDR` — valid when `S_AXI_AWVALID = 1`
- **Data channel:** `S_AXI_WDATA` — valid when `S_AXI_WVALID = 1`

The slave captures the address into a registered signal `axi_awaddr` for use if data arrives later:

```verilog
axi_awaddr <= S_AXI_AWADDR;   // non-blocking: takes effect NEXT clock cycle
```

Because this is non-blocking, `axi_awaddr` always lags one cycle behind `S_AXI_AWADDR`.

**The correct address-matching pattern** (used by the auto-generated `slv_reg2`/`slv_reg3` case block):
```verilog
case ( (S_AXI_AWVALID) ? S_AXI_AWADDR[...] : axi_awaddr[...] )
```
"Use the live address if it's valid right now; otherwise fall back to the registered copy."

**The broken pattern** in the hand-written `slv_reg0`/`slv_reg1` blocks:
```verilog
else if(slv_reg_wren & axi_awaddr[...] == 0)
    slv_reg0 <= S_AXI_WDATA;
```
Always uses the registered (one-cycle-delayed) value. For back-to-back writes, this creates a one-cycle timing mismatch.

### Trace of the Failure

Software issues two back-to-back writes:
```c
Xil_Out32(baseAddress + 8, myChar);  // Write #1: addr=8, data=0x48 ('H')
Xil_Out32(baseAddress + 0, 0x1);     // Write #2: addr=0, data=0x1
```

**Write #1 (addr=8, data=0x48):**
- Live `S_AXI_AWADDR = 8`. `axi_awaddr` still = `0` (non-blocking lag — not updated until next cycle).
- `slv_reg2` case block uses live address → writes `0x48` to `slv_reg2`. ✅
- `slv_reg0` block checks stale `axi_awaddr == 0` → condition passes → `slv_reg0` written with `0x48`. ❌
- End of cycle: `axi_awaddr` updates to `8`.

**Write #2 (addr=0, data=0x1):**
- Live `S_AXI_AWADDR = 0`. `axi_awaddr = 8` (from Write #1 — still one cycle stale).
- `slv_reg0` block checks `axi_awaddr == 0` → sees `8` → condition fails → write silently dropped. ❌
- `slv_reg0` stays at `0x48`. `sendDataValid = slv_reg0[0] = 0`. Hardware FSM never triggered. Infinite hang.

### Fix

Use the same live-address mux in both dedicated register blocks:

```verilog
// slv_reg0
else if(slv_reg_wren && ((S_AXI_AWVALID) ? S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] : axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]) == 0)
    slv_reg0 <= S_AXI_WDATA;

// slv_reg1
else if(slv_reg_wren && ((S_AXI_AWVALID) ? S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] : axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]) == 1)
    slv_reg1 <= S_AXI_WDATA;
```

### Lesson

**Whenever you write a custom register block in an AXI-Lite slave instead of using the auto-generated case statement**, the address-matching condition must use:

```verilog
(S_AXI_AWVALID) ? S_AXI_AWADDR[...] : axi_awaddr[...]
```

Not just `axi_awaddr[...]` alone. `axi_awaddr` is always one cycle behind the live bus. For back-to-back transactions (the common case in any C driver that writes multiple registers sequentially), the lag causes the wrong register to be written — your data goes to the previous transaction's address, and the intended address is silently missed.

This bug does not appear in the auto-generated register blocks because those already use the correct mux. It only bites when you add custom register blocks by hand and forget to replicate the full address-match pattern from the template.

---

## Diagnostic Technique: `xil_printf` Register Dump

When the Vitis debugger's memory views produce ambiguous results (endian display issues, stale cached reads, display-layer formatting), a direct `xil_printf` of the actual register values is faster and more reliable:

```c
xil_printf("reg0=%08x reg1=%08x reg2=%08x reg3=%08x\n",
    Xil_In32(baseAddress + 0),
    Xil_In32(baseAddress + 4),
    Xil_In32(baseAddress + 8),
    Xil_In32(baseAddress + 12));
```

Insert this immediately before the polling loop, run without breakpoints, and read the UART output. The values are unambiguous — the CPU itself is doing the read and printing the literal 32-bit hex value, bypassing any debugger display layer. This single output was what revealed Bug #5 after all other approaches produced ambiguous results.
