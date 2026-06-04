/*============================================================================
  i8041 MCU Top-Level Wrapper

  Instantiates upi41_core (UPI-41 variant of T48 with host-bus interface),
  wired to a dual-port program memory (mcu_pmem) and the main system bus
  (host-side slave interface for 6502 access at $E5xx).

  Port assignments:
    - xtal_i / xtal_en_i / reset_i: clock & reset from main PLL + clock divider
    - Host interface (cs_n, rd_n, wr_n, a0, db_*): 6502 access at $E5xx
    - Tape interface (t0_i, t1_i, p1_*, p2_*, prog_n): to tape_streamer (task 17)
    - Program ROM (rom_we, rom_addr_w, rom_data_w): written by rom_loader (task 25)

  Generics:
    - xtal_div_3_g=1: T48 divides XTAL by 3 then /5 for machine states
    - register_mnemonic_g=1: registered instruction output
    - sample_t1_state_g=4: T1 sampling state
    - is_upi_type_a_g=0: standard UPI-41 (not type-A variant)

  Clock notes:
    - clk_sys: main system clock (typically 48 MHz for MiSTer)
    - ce_hclk: 6 MHz clock enable (from clock_div.v, line ~100)
    - Both xtal_i and clk_i get clk_sys; xtal_en_i and en_clk_i get ce_hclk
    - T48 internally divides by 3 then /5 → ~400 kHz machine state rate
    - Effective i8041 ALE rate ≈ 400 kHz (matches documented 6 MHz XTAL / 15)

  Reset polarity:
    - reset_i to upi41_core is ACTIVE-HIGH (standard T48 convention)
    - External reset_n is inverted at top-level port
============================================================================*/

`timescale 1 ps / 1 ps

module i8041_top (
    input  wire        clk_sys,        // 96 MHz system clock (rom-load / host domain)
    input  wire        ce_hclk,        // 6 MHz clock enable (legacy; unused after real-clock fix)
    input  wire        clk_8041,       // MCU-CLK-REALCLK-2026-06-04: dedicated ~8 MHz REAL clock for the 8041
    input  wire        reset_n,        // active-low external reset

    // Host (main 6502) slave interface
    // Driven by task 17's decode of $E5xx
    input  wire        cs_n,           // Chip Select (active-low)
    input  wire        rd_n,           // Read Enable (active-low)
    input  wire        wr_n,           // Write Enable (active-low)
    input  wire        a0,             // Address bit 0 (selects register)
    input  wire [7:0]  host_din,       // 6502 data bus → MCU
    output wire [7:0]  host_dout,      // MCU data bus → 6502
    output wire [7:0]  host_sts,       // DBBSTS exposure 2026-05-30: real STATUS reg (OBF/IBF/F0/F1/ST4-7)
    output wire        host_dout_oe,   // Output enable for MCU (tristate control)
    output wire        sync_o,         // SYNC output (ALE signal)

    // Tape / cassette / input multiplexer interface (to task 17)
    input  wire        t0_i,           // Timer 0 input
    input  wire        t1_i,           // Timer 1 input
    input  wire [7:0]  p1_i,           // Port 1 input
    output wire [7:0]  p1_o,           // Port 1 output
    output wire        p1_low_imp,     // Port 1 low-impedance drive (open-drain style)
    input  wire [7:0]  p2_i,           // Port 2 input (bit 7 = DACK_N for DMA)
    output wire [7:0]  p2_o,           // Port 2 output
    output wire        p2l_low_imp,    // Port 2 low-byte low-impedance drive
    output wire        p2h_low_imp,    // Port 2 high-byte low-impedance drive
    output wire        prog_n,         // Program mode (inverted; normally low)

    // Program ROM loader interface (task 25)
    // Port A: write-only (rom_loader writes cassmcu1.cpu)
    // Port B: read-only (upi41_core fetches instructions)
    input  wire        rom_we,         // BRAM write enable
    input  wire [9:0]  rom_addr_w,     // BRAM write address (A)
    input  wire [7:0]  rom_data_w,     // BRAM write data (A)

    // DIAG-2026-06-03: expose MCU program counter (pmem fetch addr) for the handshake probe
    output wire [10:0] pmem_addr_o
);

    //--------------------------------------------------------------------------
    // Internal signals
    //--------------------------------------------------------------------------

    wire [10:0] pmem_addr;    // Program memory address (11 bits in UPI41)
    wire [7:0]  pmem_data;    // Program memory data (8 bits read)
    assign pmem_addr_o = pmem_addr;   // DIAG-2026-06-03: MCU PC out for probe

    // MCU-CLK-FIX-2026-06-03: the core's XTAL/3 clock-enable output, fed back
    // into en_clk_i (matches canonical t8041_notri.vhd: en_clk_i => xtal3_s;
    // xtal3_o => xtal3_s). Keeps the machine-state FSM phase-locked to the
    // XTAL sub-phases that place ALE/PSEN/RD/WR.
    wire        mcu_xtal3;

    //--------------------------------------------------------------------------
    // Program Memory (dual-port BRAM)
    // Port A: written by rom_loader
    // Port B: read by upi41_core
    //--------------------------------------------------------------------------

    mcu_pmem u_pmem (
        .clk_a      (clk_sys),      // Port A write: rom_loader (clk_sys)
        .we_a       (rom_we),
        .addr_a     (rom_addr_w),
        .din_a      (rom_data_w),
        .clk_b      (clk_8041),     // Port B read: 8041 instruction fetch (real 8041 clock)
        .addr_b     (pmem_addr),
        .dout_b     (pmem_data)
    );

    //--------------------------------------------------------------------------
    // UPI41 Core Instantiation
    //
    // Entity: upi41_core
    // File:   rtl/cpu/T48/upi41_core.vhd
    //
    // This is the UPI-41 variant of the T48 core, which includes:
    //   - Host-bus interface (cs_n, rd_n, wr_n, a0, db_i/o/dir)
    //   - Program and data memory interfaces
    //   - Port 1 and Port 2 I/O
    //   - Timer module (T0 overflow, T1 input)
    //   - Flag storage (F0, F1) accessed via host bus
    //   - Input buffer (IBF) / Output buffer (OBF) flags
    //
    // The host-bus is FULLY INSIDE the core via upi41_db_bus submodule (line 352).
    // CS_N/RD_N/WR_N/A0 directly decode register addresses and generate
    // dmem-style read/write strobes for the internal I/O register bank.
    //
    // Generics:
    //   - xtal_div_3_g=1: T48 divides XTAL by 3, then /5 internally for mstate
    //   - register_mnemonic_g=1: instruction mnemonic stored in flip-flops (not used here)
    //   - sample_t1_state_g=4: T1 input sampled in MSTATE4
    //   - is_upi_type_a_g=0: Standard UPI-41 (vs. type-A with extra DMA features)
    //--------------------------------------------------------------------------

    upi41_core u_upi41 (
        // Clock & Reset
        // MCU-CLK-REALCLK-2026-06-04: feed a REAL clock with xtal_en='1' (the canonical T48
        // contract, matching Arcade-JunoFirst's working 8039). clk_sys+ce_hclk broke multi-cycle
        // ADD carry (the 8041 range-rejected valid commands). Now clk_i==xtal_i==clk_8041.
        .xtal_i         (clk_8041),     // REAL ~8 MHz clock (was clk_sys)
        .xtal_en_i      (1'b1),         // always enabled (was ce_hclk)
        // DIAG-REVERT-2026-05-30: T48 res_active_c='0' => reset is ACTIVE-LOW. The ~ here held the
        // core in reset during NORMAL run (reset_n=1 -> ~reset_n=0 = res_active_c => permanent reset),
        // so ibf_q/status_q were frozen at 0 and the MCU never executed. Pass reset_n straight.
        // .reset_i        (~reset_n),     // ORIGINAL (WRONG: comment claimed active-high)
        .reset_i        (reset_n),      // FIXED: active-low, matches T48 res_active_c='0'

        // Host interface (6502 bus at $E5xx)
        // These pins are decoded by upi41_db_bus inside the core
        .cs_n_i         (cs_n),         // Chip Select
        .rd_n_i         (rd_n),         // Read strobe
        .wr_n_i         (wr_n),         // Write strobe
        .a0_i           (a0),           // Address bit 0 (0=command, 1=data)
        .db_i           (host_din),     // Data bus input
        .db_o           (host_dout),    // Data bus output
        .sts_o          (host_sts),     // DBBSTS exposure 2026-05-30
        .db_dir_o       (host_dout_oe), // Output enable (active-high)
        .sync_o         (sync_o),       // Sync/ALE output (strobes addresses)

        // Timer & external inputs
        .t0_i           (t0_i),         // Timer 0 input (tape clock sense)
        .t1_i           (t1_i),         // Timer 1 input

        // Port 1 (input multiplexer for joystick/coin/start)
        .p1_i           (p1_i),
        .p1_o           (p1_o),
        .p1_low_imp_o   (p1_low_imp),

        // Port 2 (control signals for tape motor, LED, etc.)
        .p2_i           (p2_i),
        .p2_o           (p2_o),
        .p2l_low_imp_o  (p2l_low_imp),
        .p2h_low_imp_o  (p2h_low_imp),

        // Program mode flag (active-low, inverted on output)
        .prog_n_o       (prog_n),

        // Core clock & enable (separate from xtal for flexibility)
        // Some designs use clk_i != xtal_i, but we tie them here
        .clk_i          (clk_8041),     // Core clock = REAL 8041 clock (was clk_sys)
        // MCU-CLK-FIX-2026-06-03: en_clk_i was tied to ce_hclk (same net as
        // xtal_en_i) with xtal3_o discarded. That ran the machine-state FSM at
        // ce_hclk while the XTAL-phase / ALE / RD / WR logic ran at ce_hclk/3 —
        // 3x desync, so the MCU executed but garbled instruction sequencing
        // (dispatch at $0ED / jmpp never reached OUT DBB -> CASSETTE ERROR 59).
        // Feed the core's own XTAL/3 output back in, per canonical t8041_notri.
        // TO REVERT: restore the two ORIGINAL lines below and delete the FIXED pair.
        // .en_clk_i       (ce_hclk),      // ORIGINAL (WRONG)
        // .xtal3_o        (),             // ORIGINAL (WRONG: xtal3 discarded)
        .en_clk_i       (mcu_xtal3),    // FIXED: en_clk = core's XTAL/3 enable
        .xtal3_o        (mcu_xtal3),    // FIXED: feedback loop (== canonical)

        // Program memory interface (connects to mcu_pmem)
        .pmem_addr_o    (pmem_addr),    // 11-bit address (i8041 is 2K max; we use 10 bits)
        .pmem_data_i    (pmem_data),    // 8-bit instruction data

        // Data memory interface (unused; i8041 has internal 64 bytes only)
        // dmem accesses are handled internally; we don't provide external SRAM
        .dmem_addr_o    (),             // Data memory address (not used)
        .dmem_we_o      (),             // Data memory write enable (not used)
        .dmem_data_i    (8'h00),        // Data memory read data (tie to 0; internal RAM only)
        .dmem_data_o    (),             // Data memory write data (not used)

        // Generics (via port-map default)
        // .xtal_div_3_g => 1,
        // .register_mnemonic_g => 1,
        // .sample_t1_state_g => 4,
        // .is_upi_type_a_g => 0
    );

endmodule
