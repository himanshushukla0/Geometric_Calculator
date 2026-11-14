# Geometric Formula Calculator – Nexys A7 (Verilog)

A geometric-formula calculator for the Digilent Nexys A7, written in Verilog in a single source file `geo_calc.v`. Two 5-bit integer inputs are set on the switches, one of 8 formulas is selected with BTNU / BTND, and the answer is shown on the 8-digit seven-segment display with one decimal place.

## Files

| File | Purpose |
|---|---|
| `geo_calc.v` | All 9 modules. `top` is the top module. |
| `geo_calc.xdc` | Pin constraints for the Nexys A7 |

## Top-level ports (`module top`)

| Port | Width | Dir | Board resource | Use |
|---|---|---|---|---|
| `CLK100MHZ` | 1 | in | 100 MHz oscillator | System clock for every module |
| `CPU_RESETN` | 1 | in | Red CPU reset button | Active-low reset. Inverted inside `top` to make `rst`. |
| `SW` | 10 | in | SW[9:0] | `SW[4:0]` = input **A**, `SW[9:5]` = input **B**, each 0–31 |
| `BTNU` | 1 | in | Up button | Next formula |
| `BTND` | 1 | in | Down button | Previous formula |
| `LED` | 3 | out | LED[2:0] | Current formula number in binary |
| `AN` | 8 | out | SSD anodes | Active low, one digit enabled at a time |
| `SEG` | 7 | out | SSD segments | `{g,f,e,d,c,b,a}`, active low |
| `DP` | 1 | out | SSD decimal point | Active low, lit only on digit 1 |

SW[15:10] are not used and are not in the port list or the XDC.

## Formulas (`module geo_alu`)

Every result is stored as the answer × 10, so one decimal place is carried through the design. π is handled with fixed-point constants: 10π ≈ 32170/1024 and 20π ≈ 64340/1024. The `>> 10` divides by 1024.

| Mode | Formula | Meaning | Verilog expression | Max at a = b = 31 |
|---|---|---|---|---|
| F0 | a·b | Rectangle area (square if b = a) | `ab * 10` | 961.0 |
| F1 | 2(a+b) | Rectangle perimeter | `a_pb * 20` | 124.0 |
| F2 | a·b/2 | Triangle area | `ab * 5` | 480.5 |
| F3 | π·a·b | Ellipse area (circle if b = a) | `(ab * 32170) >> 10` | 3019.0 |
| F4 | 2π·a | Circumference (B ignored) | `(a * 64340) >> 10` | 194.7 |
| F5 | a²·b | Box volume (cube if b = a) | `ab * a * 10` | 29791.0 |
| F6 | π·a²·b | Cylinder volume (a = radius, b = height) | `(ab * a * 32170) >> 10` | 93591.4 |
| F7 | 2π·a·b | Cylinder curved surface | `(ab * 64340) >> 10` | 6038.1 |

where `ab = a * b` (10 bits) and `a_pb = a + b` (6 bits).

All 8 expressions are computed in parallel, a `case (sel)` selects one, and the selection is registered into `result[19:0]` on the clock edge. The fractional part is truncated, not rounded.

For a square, circle or cube, set B equal to A.

## Why inputs are 0–31

Two SSD digits show the formula code, leaving 6 digits for the answer. With one decimal place the largest displayable answer is **99,999.9** (scaled value 999,999).

| Input width | Range | Largest answer (F6) | Fits? |
|---|---|---|---|
| 6 bits | 0–63 | ≈ 785,000 | No |
| 5 bits | 0–31 | 93,591.4 | Yes |

With 5-bit inputs nothing can exceed the display, so the design has no overflow logic. The largest scaled value, 935,914, fits in the 20-bit `result` bus (max 1,048,575).

## Formula selection

| Button | Action |
|---|---|
| BTNU | Next: F0 → F1 → … → F7 → F0 |
| BTND | Previous: F0 → F7 → F6 → … |
| CPU_RESETN | Back to F0 |

```
BTNU ─► debounce ─► edge_det ─► up_pulse ─┐
                                           ├─► mode_ctrl ─► sel[2:0]
BTND ─► debounce ─► edge_det ─► dn_pulse ─┘
```

- `debounce` (one instance per button): the button is passed through two flip-flops, then a 20-bit counter runs while the input differs from the output. The output changes only when the input has been stable for `COUNT_MAX = 1_000_000` clocks (10 ms at 100 MHz).
- `edge_det`: `pulse = level & ~prev`, one clock-cycle pulse per press, however long the button is held.
- `mode_ctrl`: 3-bit counter. `up` adds 1, `dn` subtracts 1, both pressed together is ignored. Being 3 bits it wraps on its own (7 + 1 = 0, 0 − 1 = 7).

`sel` drives `geo_alu`, `display_format` and `LED[2:0]`.

## Display

### Layout

Digit 7 is leftmost, digit 0 is rightmost.

```
 digit:  7   6   5   4   3   2   1   0
        [F] [n] [_] [_] [_] [x] [x].[x]
         mode     ─────── answer ───────
                              units  tenths
```

- Digit 7 shows `F`, digit 6 shows `sel`.
- Digits 5–0 show the 6 BCD digits of `result`. The decimal point is lit on digit 1, so digit 0 is the tenths.
- Leading zeros are blanked on digits 5–2 only. Digits 1 and 0 always show, so zero displays as `0.0` and a small answer as `0.5`.

### Examples

F0, a = 7, b = 7 → 49 (result = 490)
```
┌───┬───┬───┬───┬───┬───┬───┬───┐
│ F │ 0 │   │   │   │ 4 │ 9.│ 0 │
└───┴───┴───┴───┴───┴───┴───┴───┘
```

F2, a = 5, b = 5 → 12.5 (result = 125)
```
┌───┬───┬───┬───┬───┬───┬───┬───┐
│ F │ 2 │   │   │   │ 1 │ 2.│ 5 │
└───┴───┴───┴───┴───┴───┴───┴───┘
```

F3, a = 3, b = 3 → 28.27… (result = 282)
```
┌───┬───┬───┬───┬───┬───┬───┬───┐
│ F │ 3 │   │   │   │ 2 │ 8.│ 2 │
└───┴───┴───┴───┴───┴───┴───┴───┘
```

F2, a = 1, b = 1 → 0.5 (result = 5)
```
┌───┬───┬───┬───┬───┬───┬───┬───┐
│ F │ 2 │   │   │   │   │ 0.│ 5 │
└───┴───┴───┴───┴───┴───┴───┴───┘
```

F6, a = 31, b = 31 → 93,591.4 (result = 935914, the largest possible)
```
┌───┬───┬───┬───┬───┬───┬───┬───┐
│ F │ 6 │ 9 │ 3 │ 5 │ 9 │ 1.│ 4 │
└───┴───┴───┴───┴───┴───┴───┴───┘
```

### Digit codes and segment patterns

`display_format` sends a 4-bit code per digit to `ssd_mux` in `digits[31:0]` (digit 7 in `[31:28]`, digit 0 in `[3:0]`).

| Code | Symbol | `SEG` = {g,f,e,d,c,b,a} |
|---|---|---|
| 0–9 | number | standard patterns, e.g. 0 = `1000000` |
| 10 (`CH_F`) | F | `0001110` |
| 15 (`CH_BLANK`) | blank | `1111111` |

Segments, anodes and DP are active low, so 0 = on.

## Architecture

```
SW[9:0] ───► input_sync ───► a[4:0], b[4:0] ──────────────┐
                                                           ▼
BTNU ─► debounce ─► edge_det ─┐                       ┌─────────┐ result[19:0] ┌─────────┐ bcd[23:0]
BTND ─► debounce ─► edge_det ─┤                       │ geo_alu │─────────────►│ bin2bcd │─────┐
                              ▼                       └─────────┘              └─────────┘     │
                        ┌───────────┐  sel[2:0]            ▲                                   ▼
                        │ mode_ctrl │──┬───────────────────┘                        ┌────────────────┐
                        └───────────┘  ├───────────────────────────────────────────►│ display_format │
                                       └──► LED[2:0]                                └───────┬────────┘
                                                                                            ▼ digits[31:0]
                                                                                      ┌─────────┐
                                                                                      │ ssd_mux │─► AN, SEG, DP
                                                                                      └─────────┘
```

All modules use `clk` (100 MHz) and the synchronous, active-high `rst`.

### Modules in `geo_calc.v`

| # | Module | Inputs → Outputs | What it does |
|---|---|---|---|
| 1 | `top` | board pins | Instantiates and wires everything; `rst = ~CPU_RESETN`; `LED = sel` |
| 2 | `input_sync` | `sw[9:0]` → `a[4:0]`, `b[4:0]` | Two-flip-flop synchronizer so the asynchronous switches are safe to use |
| 3 | `debounce` ×2 | `btn` → `btn_clean` | Output follows input after 10 ms of stability (`COUNT_MAX` = 1,000,000) |
| 4 | `edge_det` ×2 | `level` → `pulse` | One-clock pulse on the rising edge |
| 5 | `mode_ctrl` | `up`, `dn` → `sel[2:0]` | 3-bit up/down counter, wraps |
| 6 | `geo_alu` | `a`, `b`, `sel` → `result[19:0]` | All 8 formulas in parallel, 8-to-1 mux, registered output |
| 7 | `bin2bcd` | `bin[19:0]` → `bcd[23:0]` | Double-dabble FSM: IDLE → SHIFT (20 cycles) → DONE, restarts automatically |
| 8 | `display_format` | `bcd`, `sel` → `digits[31:0]` | Adds `F` and `sel`, blanks leading zeros on digits 5–2 |
| 9 | `ssd_mux` | `digits` → `an`, `seg`, `dp` | Scans the 8 digits, 7-segment decoder, DP on digit 1 |

### Data flow

Switches → `input_sync` → `geo_alu` computes the answer × 10 → `bin2bcd` converts it to 6 BCD digits → `display_format` adds `Fn` and blanking → `ssd_mux` drives one digit at a time.

### Timing details from the code

- `input_sync` adds 2 clock cycles of delay.
- `geo_alu` adds 1 cycle (the output register).
- `bin2bcd` takes 22 cycles per conversion (1 IDLE + 20 SHIFT + 1 DONE) and runs continuously, so `bcd` updates about every 0.22 µs.
- `ssd_mux` uses a 20-bit free-running counter (`REFRESH_BITS = 20`); its top 3 bits select the digit. Each digit is on for 2¹⁷ clocks ≈ 1.31 ms, so the whole display refreshes every ≈ 10.5 ms (≈ 95 Hz), above the flicker threshold.
- A switch change is therefore visible within about 11 ms. A button press is registered 10 ms after the contact settles.

### How binary becomes decimal (`bin2bcd`)

The 20-bit value is loaded into the low part of a 44-bit shift register `sh`, with 24 BCD bits of zeros above it. For each of the 20 steps, every BCD nibble that is 5 or more gets 3 added (function `add3`), then the whole register shifts left by one. After 20 steps `sh[43:20]` holds the 6 decimal digits and is copied to `bcd`, so the display never sees a half-finished conversion.

## Walkthrough

With A = 7 (`SW[4:0]` = 00111) and B = 4 (`SW[9:5]` = 00100), pressing BTNU repeatedly:

| Mode | Calculation | Display |
|---|---|---|
| F0 | 7 × 4 | `F0 28.0` |
| F1 | 2 × (7 + 4) | `F1 22.0` |
| F2 | 7 × 4 / 2 | `F2 14.0` |
| F3 | π × 7 × 4 | `F3 87.9` |
| F4 | 2π × 7 | `F4 43.9` |
| F5 | 7 × 7 × 4 | `F5 196.0` |
| F6 | π × 7² × 4 | `F6 615.7` |
| F7 | 2π × 7 × 4 | `F7 175.9` |

The ALU recomputes continuously, so flipping a switch changes the answer immediately without pressing any button.

## Building in Vivado

1. Create an RTL project for the Nexys A7 (A7-100T: `xc7a100tcsg324-1`; A7-50T: `xc7a50ticsg324-1L`).
2. Add `geo_calc.v` as a design source and `geo_calc.xdc` as a constraints file.
3. Set `top` as the top module.
4. Run synthesis, implementation and bitstream generation, then program the board.

## Simulation

Add `tb_geo_calc.v` as a simulation source and set `tb_geo_calc` as the simulation top. It drives a 100 MHz clock, releases `CPU_RESETN`, sets A = B = 3 and presses BTNU 8 times. The testbench uses `defparam` to shorten `COUNT_MAX` and `REFRESH_BITS` so the run takes microseconds instead of milliseconds. Expected `result` values:

| Mode | `result` | Displayed |
|---|---|---|
| F0 | 90 | 9.0 |
| F1 | 120 | 12.0 |
| F2 | 45 | 4.5 |
| F3 | 282 | 28.2 |
| F4 | 188 | 18.8 |
| F5 | 270 | 27.0 |
| F6 | 848 | 84.8 |
| F7 | 565 | 56.5 |

If `top` is simulated directly without the testbench, all signals show `X`/`Z` until the clock, reset, switches and buttons are forced.

## Known limits

- Tenths digit is truncated, not rounded (28.27 → 28.2).
- Inputs are limited to 0–31 so no answer can exceed the 6 answer digits.
- F3 and F5 give a circle or cube only when B = A. F4 uses only A.
- Pressing BTNU and BTND in the same clock cycle is ignored.
