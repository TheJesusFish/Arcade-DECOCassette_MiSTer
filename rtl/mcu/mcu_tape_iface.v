/*============================================================================
  MCU ↔ Tape ↔ Main CPU Interface

  Glue logic connecting:
  - i8041 MCU (P1, P2, T0, T1 ports) to tape_streamer (task 16)
  - Main 6502 CPU ($E5xx address space) to i8041 host-bus interface
  - Dongle lower-nibble (task 18) to CPU read response

  Pin mappings per decocass_m.cpp (lines 1734-1835):

  P1 (tape data/status in; motor/direction/speed out):
    P1.0 ← tape_data       (MAME: ~data bit if set, see decocass_m.cpp line 1778)
    P1.1 ← tape_clock      (MAME: ~clk bit if set, line 1779)
    P1.2 ← tape_bot        (MAME: ~BOT# if set, line 1780)
    P1.3 ← tape_eot        (MAME: ~EOT# if set, line 1781)
    P1.4 → tape_motor_on   (MAME: ~motor if set, line 1782; inverted in schematic)
    P1.5 → tape_direction  (MAME: ~forward if set, line 1783; inverted)
    P1.6/7 → speed[1:0]    (MAME: speed control, lines 1784-1785)

  P2 (input mux select out; status in):
    P2[3:0] → input mux select (to inputs.v task 23)
    P2[7:4] ← status bits (from tape_streamer or MCU; returned as upper nibble of $E5xx read)

  T0/T1 (timer inputs):
    T0 ← tape direction sensor (TODO: verify mapping in MAME)
    T1 ← tape status bit (TODO: verify mapping in MAME)

  $E5xx Host Bus Protocol:
    CPU write $E5xx:  cs_n/wr_n strobed, A0 = cpu_addr[0], host_din = cpu_dout
    CPU read $E5xx:   cs_n/rd_n strobed, A0 = cpu_addr[0], host_dout captured, combined with dongle_din_low4

  Clock domains:
    - clk_sys: 96 MHz (all Verilog)
    - ce_hclk: 6 MHz MCU clock enable (1 per T48 machine state)
    - ce_hclk1: 3 MHz main 6502 clock enable
    - ce_tape: 4.8 kHz tape data rate
    One ce_hclk1 pulse spans exactly 2 ce_hclk pulses; stretch cpu strobes accordingly.

============================================================================*/

`timescale 1 ps / 1 ps

module mcu_tape_iface (
    input  wire        clk_sys,
    input  wire        ce_hclk,        // 6 MHz MCU clock enable
    input  wire        ce_hclk1,       // 3 MHz CPU clock enable
    input  wire        ce_tape,        // 4.8 kHz tape clock enable
    input  wire        reset,

    // MCU ports (to/from i8041_top)
    output wire [7:0]  mcu_p1_in,
    input  wire [7:0]  mcu_p1_out,
    output wire [7:0]  mcu_p2_in,
    input  wire [7:0]  mcu_p2_out,
    output wire        mcu_t0,
    output wire        mcu_t1,

    // MCU host-bus interface (stretched strobes to i8041_top)
    output wire        mcu_cs_n,
    output wire        mcu_rd_n,
    output wire        mcu_wr_n,
    output wire        mcu_a0,
    output wire [7:0]  mcu_dout,

    // Tape signals (to/from tape_streamer)
    output wire        tape_motor_on,
    output wire        tape_direction,
    output wire [1:0]  tape_speed_select,
    input  wire        tape_data,
    input  wire        tape_clock,
    input  wire        tape_bot,
    input  wire        tape_eot,

    // Main CPU side ($E5xx)
    input  wire        cpu_e5_re,      // Read strobe (new signal from decocass.v task 28)
    input  wire        cpu_e5_we,      // Write strobe (existing cpu_we_e5xx)
    input  wire [7:0]  cpu_addr_lo,    // Low byte of address ($E5xx)
    input  wire [7:0]  cpu_dout,       // CPU data out
    output wire [7:0]  cpu_din,        // Upper nibble = MCU status, lower = dongle

    // MCU host bus output — DBBOUT register (8-bit).
    // The dongle data path returns the i8041's host output register
    // (`upi41_master_r(0)`), NOT P2 outputs.
    input  wire [7:0]  mcu_host_dout,
    input  wire        mcu_host_dout_oe,

    // Dongle interface (downstream to task 18)
    output wire [7:0]  dongle_addr_lo,
    output wire        dongle_re,
    output wire        dongle_we,
    output wire [7:0]  dongle_dout,
    input  wire [3:0]  dongle_din_low4
);

    //------------------------------------------------------------------------
    // P1 Wiring (decocass_m.cpp lines 1734-1789)
    //
    // 2026-05-17 — REWRITE. Previous version wired tape_data/tape_clock/
    // tape_bot/tape_eot into mcu_p1_in[0..3]. That was WRONG: per MAME's
    // i8041_p1_r (decocass_m.cpp:1768-1789), P1 reads return `m_i8041_p1`
    // unchanged — i.e. whatever the MCU LAST WROTE. P1 is purely OUTPUT from
    // the MCU (tape transport control, REQ output to main CPU). Tape signals
    // do NOT come in via P1.
    //
    // P1 output bit assignments per the LOG strings at line 1742-1749:
    //   bit 0 = DATA-WRT (MCU writes data bit to tape)
    //   bit 1 = DATA-CLK (MCU writes clock to tape)
    //   bit 2 = FAST     (1 = normal speed, 0 = fast)
    //   bit 3 = (unknown, BIT3)
    //   bit 4 = REW      (1 = rewind active, 0 = forward)
    //   bit 5 = FWD      (1 = forward active, 0 = stopped)
    //   bit 6 = WREN     (write enable)
    //   bit 7 = REQ      (REQ signal to main CPU, polled via $E502 bit 0)
    //
    // For OUR tape_streamer, we need to derive motor/direction/speed from
    // P1.4/5/2 according to the MAME-decoded LOG semantics:
    //   FAST = ~P1.2 (bit 2 = 0 means fast)
    //   REW  = ~P1.4 (bit 4 = 0 means rewind active)
    //   FWD  = ~P1.5 (bit 5 = 0 means forward active)
    //   Motor on if FWD OR REW. Direction = FWD.
    //
    // Inputs to MCU's P1: all 1s (idle pull-ups; open-drain semantics).
    //------------------------------------------------------------------------
    assign mcu_p1_in = 8'hFF;   // No external drives on P1 (per MAME)

    // Decode P1 outputs into tape control. NOTE: MCU writes inverted-active
    // signals (a 0 = "asserted") per LOG comments above.
    wire fast_active = ~mcu_p1_out[2];
    wire rew_active  = ~mcu_p1_out[4];
    wire fwd_active  = ~mcu_p1_out[5];

    assign tape_motor_on     = fwd_active | rew_active;
    assign tape_direction    = fwd_active;       // 1 = forward, 0 = rewind
    // FIX 2026-05-30: speed_select now encodes MAGNITUDE only (direction is tape_direction above);
    // 00=stop, 01=normal(1x), 10=fast(7x) — matches MAME |speed| 0/1/7. Was 11=rewind (direction
    // baked in), which left fast-rewind indistinguishable from normal and the streamer ignored it.
    assign tape_speed_select = (!(fwd_active | rew_active)) ? 2'b00 :  // stopped
                               fast_active                   ? 2'b10 :  // fast (7x)
                                                               2'b01;   // normal (1x)

    //------------------------------------------------------------------------
    // P2 Wiring (decocass_m.cpp lines 1791-1835)
    //
    // 2026-05-17 — REWRITE. Previous version had mcu_p2_in[7:4] hardcoded
    // to 0, dropping the tape status bits the MCU firmware needs. Per
    // MAME's i8041_p2_r (line 1816):
    //   data = (m_i8041_p2 & ~0xe0) | m_cassette->get_status_bits();
    // So P2[7:5] are OR'd with the cassette status bits, while P2[4:0]
    // come from the MCU's own latched writes.
    //
    // From decocass_tape.cpp:288-338 (get_status_bits):
    //   bit 0x20 = BOT/EOT (set in LEADER, BOT, EOT, TRAILER regions)
    //   bit 0x40 = RCLK    (read clock — active in data region)
    //   bit 0x80 = RDATA   (read data bit)
    //
    // For our tape_streamer outputs:
    //   tape_bot (from streamer) is true in LEADER/BOT/EOT/TRAILER regions
    //   tape_eot similar
    //   tape_clock and tape_data are the serial stream
    //------------------------------------------------------------------------
    wire status_bot_eot = tape_bot | tape_eot;    // bit 5 — tape end indicator
    wire status_rclk    = tape_clock;             // bit 6 — read clock
    wire status_rdata   = tape_data;              // bit 7 — read data

    assign mcu_p2_in[7] = status_rdata;
    assign mcu_p2_in[6] = status_rclk;
    assign mcu_p2_in[5] = status_bot_eot;
    assign mcu_p2_in[4] = 1'b1;                   // IN4 (unknown source — idle pull-up)
    assign mcu_p2_in[3:0] = 4'b1111;              // P2[3:0] are MCU outputs; idle pull-up

    //------------------------------------------------------------------------
    // T0/T1 Wiring — MAME does NOT register callbacks for T0/T1 on the MCU
    // (decocass.cpp:1026-1029 only wires P1/P2). The i8041 emulator defaults
    // T0/T1 to floating-high. Match that with hardcoded 1s.
    //------------------------------------------------------------------------
    assign mcu_t0 = 1'b1;
    assign mcu_t1 = 1'b1;

    //------------------------------------------------------------------------
    // $E5xx Host Bus Protocol
    //
    // The MCU runs at ce_hclk (6 MHz), driven on clk_sys.
    // The CPU runs at ce_hclk1 (3 MHz), also on clk_sys.
    // One ce_hclk1 pulse spans exactly 2 ce_hclk pulses.
    //
    // When the CPU issues a read or write strobe (cpu_e5_re or cpu_e5_we),
    // that strobe is 1 clock (clk_sys) wide and asserted during ce_hclk1.
    // We must stretch it to 2 ce_hclk pulses (16 clk_sys clocks) so the
    // MCU sees it and latches the bus.
    //
    // Strategy:
    //   - Detect rising edge of cpu_e5_re/cpu_e5_we (on clk_sys)
    //   - Latch the strobe and A0/data
    //   - Assert cs_n=0/rd_n=0 or cs_n=0/wr_n=0 for 2 ce_hclk pulses
    //   - On rd_n, capture host_dout when host_dout_oe asserts
    //   - Return {mcu_status_high4, dongle_din_low4} as cpu_din
    //------------------------------------------------------------------------

    // Pipeline: detect ce_hclk1 edge to know when CPU strobe is fresh
    reg        ce_hclk1_r, ce_hclk1_rr;
    always @(posedge clk_sys) begin
        ce_hclk1_r  <= ce_hclk1;
        ce_hclk1_rr <= ce_hclk1_r;
    end
    wire       ce_hclk1_rising = ce_hclk1_r && !ce_hclk1_rr;

    // Latch CPU strobes on rising edge of ce_hclk1
    reg        cpu_e5_re_lat, cpu_e5_we_lat;
    reg [7:0]  cpu_addr_lo_lat, cpu_dout_lat;
    always @(posedge clk_sys) begin
        if (ce_hclk1_rising) begin
            cpu_e5_re_lat  <= cpu_e5_re;
            cpu_e5_we_lat  <= cpu_e5_we;
            cpu_addr_lo_lat <= cpu_addr_lo;
            cpu_dout_lat   <= cpu_dout;
        end
    end

    // Strobe pulse stretcher: extend to 2 ce_hclk cycles
    // ce_hclk runs at 6 MHz = 16.67 ns period (on 96 MHz clock = 10.42 ns)
    // ce_hclk @ 6 MHz means one pulse every 16 clk_sys cycles
    // Two ce_hclk pulses = 32 clk_sys cycles
    // But we're deriving from ce_hclk1, not counting clk_sys directly.
    // A simpler approach: use a counter that fires on ce_hclk edges.

    reg  [1:0] hclk_strobe_cnt;
    wire       hclk_strobe_active = (hclk_strobe_cnt != 0);

    reg        ce_hclk_r, ce_hclk_rr;
    always @(posedge clk_sys) begin
        ce_hclk_r  <= ce_hclk;
        ce_hclk_rr <= ce_hclk_r;
    end
    wire       ce_hclk_rising = ce_hclk_r && !ce_hclk_rr;

    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            hclk_strobe_cnt <= 0;
        end else if ((cpu_e5_re_lat || cpu_e5_we_lat) && !hclk_strobe_active) begin
            // Initiate strobe: count 2 ce_hclk pulses
            if (ce_hclk_rising)
                hclk_strobe_cnt <= 2;
        end else if (ce_hclk_rising && hclk_strobe_active) begin
            hclk_strobe_cnt <= hclk_strobe_cnt - 1;
        end
    end

    // Drive MCU host bus during strobe window (exposed via output ports)
    // cs_n, rd_n, wr_n are active-low; we assert them when strobing
    assign     mcu_cs_n  = ~hclk_strobe_active;
    assign     mcu_rd_n  = ~(hclk_strobe_active && cpu_e5_re_lat);
    assign     mcu_wr_n  = ~(hclk_strobe_active && cpu_e5_we_lat);
    assign     mcu_a0    = cpu_addr_lo_lat[0];
    assign     mcu_dout  = cpu_dout_lat;

    // Capture MCU host_dout on read completion
    // When a read strobe completes, host_dout_oe should assert and hold data.
    // We'll capture it after the strobe window and return it for 1 CPU cycle.
    // TODO: receive host_dout and host_dout_oe from i8041_top; capture and hold.

    reg [7:0] mcu_dout_read;  // Latched read data from MCU
    // TODO: capture mcu read data after read strobe completes

    //------------------------------------------------------------------------
    // Dongle Lower-Nibble Integration
    //------------------------------------------------------------------------
    // The main CPU's $E5xx read combines:
    //   Upper nibble: MCU P2[7:4] status bits
    //   Lower nibble: Dongle-specific encryption (from task 18)
    //
    // We proxy the read/write strobes and address to the dongle module
    // and return the combined result.

    assign dongle_addr_lo = cpu_addr_lo;
    assign dongle_re      = cpu_e5_re;
    assign dongle_we      = cpu_e5_we;
    assign dongle_dout    = cpu_dout;

    // Return result to main CPU — MAME splits behavior on (offset & E5XX_MASK)
    // where E5XX_MASK = 0x02 (decocass_m.cpp:212):
    //
    //   (offset & 2) == 2  → STATUS byte composed from MCU/cassette state
    //                        (decocass_m.cpp:1199-1213)
    //   (offset & 2) == 0  → dongle data path (decocass_m.cpp:1227-1233)
    //
    // Until 2026-05-17 this module returned `{mcu_p2_out[7:4], dongle_din_low4}`
    // for EVERY $E5xx read regardless of offset, so BIOS polls of $E502 STATUS
    // (cassette-present, REQ/, EOT/, ERR/) received garbage and BIOS stalled
    // immediately after the palette-clear phase. Symptom: solid-black screen
    // with palette-swatch overlay showing every entry black (BIOS only ever
    // wrote 0xFF clearing pattern, never reached "write real colors").
    //
    // Status byte mapping (MAME decocass_m.cpp:1204-1212):
    //   D7 = !cassette_present   (active-low; 0 = present)
    //   D6 = 1                   (floating input)
    //   D5 = 1                   (floating input)
    //   D4 = bot_eot             (BOT/EOT direct from drive — bit 5 of
    //                             m_cassette->get_status_bits()))
    //   D3 = m_i8041_p2[2]       (P22 = ERR/)
    //   D2 = m_i8041_p2[1]       (P21 = EOT/)
    //   D1 = m_i8041_p2[0]       (P20 = FNO/)
    //   D0 = m_i8041_p1[7]       (P17 = REQ/)
    //
    // Cassette is always "present" in this system (BRAM-loaded image), so
    // wire cassette_present_n = 0. bot_eot from tape signals.

    wire        cassette_present_n = 1'b0;    // 0 = present (active-low)
    wire        bot_eot            = tape_bot | tape_eot;

    wire [7:0]  e5xx_status_byte = {
        cassette_present_n,     // D7
        1'b1,                   // D6 floating
        1'b1,                   // D5 floating
        bot_eot,                // D4
        mcu_p2_out[2],          // D3 ERR/
        mcu_p2_out[1],          // D2 EOT/
        mcu_p2_out[0],          // D1 FNO/
        mcu_p1_out[7]           // D0 REQ/
    };

    wire        e5xx_is_status = (cpu_addr_lo[1] == 1'b1);   // E5XX_MASK = 0x02

    // Latch MCU host data when MCU is presenting it. Per
    // upi41_db_bus.vhd:256-257:
    //     db_o <= dbbout_q when a0_i = '0' else status_q;
    // mcu_host_dout already carries DBBOUT (for $E5x0 reads) or DBBSTS
    // (for $E5x1 reads) based on mcu_a0 = cpu_addr_lo_lat[0]. We just
    // latch whichever register the i8041 presented during the bus stretch.
    reg [7:0] latched_host_dout;
    always @(posedge clk_sys or posedge reset) begin
        if (reset)
            latched_host_dout <= 8'h00;
        else if (mcu_host_dout_oe)
            latched_host_dout <= mcu_host_dout;
    end

    assign cpu_din = e5xx_is_status
                     ? e5xx_status_byte
                     : latched_host_dout;

    //------------------------------------------------------------------------
    // Summary of TODO items
    //------------------------------------------------------------------------
    // TODO(verify-with-mame): P2[7:4] status bit sources (tape BOT/EOT, etc.)
    // TODO(verify-with-mame): T0/T1 timer input mapping in decocass_m.cpp
    // TODO(new-signal-decocass.v): Add cpu_re_e5xx strobe (currently only cpu_we_e5xx exists)
    // TODO(new-signal-decocass.v): Expose mcu_cs_n, mcu_rd_n, mcu_wr_n, mcu_a0 to i8041_top
    // TODO(new-signal-i8041_top): Expose host_dout and host_dout_oe from upi41_core

endmodule
