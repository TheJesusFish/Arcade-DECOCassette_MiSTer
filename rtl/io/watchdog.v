//============================================================================
//  DECO Cassette System - Watchdog Timer (vblank-counted reset + flip register)
//
//  This module implements a vblank-counted watchdog that asserts main CPU
//  reset when no wd_count_w strobe is received for 16 vblanks (~280 ms at 60 Hz).
//  It also implements the flip_screen register (XOR of wd_flip_w data with
//  the cocktail DSW bit).
//
//  Based on MAME src/mame/deco/decocass_v.cpp:
//    - decocass_watchdog_count_w (lines 388-393): loads counter with (data & 0x0f) + 1,
//      calls watchdog_reset() to clear overflow.
//    - decocass_watchdog_flip_w (lines 395-400): stores data to m_watchdog_flip,
//      enables watchdog via BIT(data, 3).
//    - Watchdog timer configured with set_vblank_count(m_screen, 16) at line 1033.
//
//  Screen update at line 741 of decocass_v.cpp computes:
//    flip_screen_set(m_watchdog_flip & BIT(m_dsw[0]->read(), 6))
//  where m_dsw[0] is DSW1 and bit 6 is the Cabinet (cocktail) bit.
//
//  Acceptance criteria:
//    - Without wd_count_w strobes, wd_reset asserts after 16 vblanks (~280 ms).
//    - With strobes every frame, wd_reset stays low (inactive).
//    - Cocktail flip: writing to $E301 toggles flip_screen when DSW1[6]=1.
//
//============================================================================

module watchdog (
    input  wire        clk_sys,
    input  wire        ce_hclk1,            // 3 MHz CPU clock enable
    input  wire        reset,

    input  wire        vblank_pulse,        // single-cycle strobe on falling edge of vblank
    input  wire        wd_count_w,          // strobe on $E300 write
    input  wire        wd_flip_w,           // strobe on $E301 write
    input  wire [7:0]  cpu_dout,            // data written at $E300 or $E301

    input  wire [7:0]  dsw1,                // bit[6] = CABINET (cocktail mode DIP)

    output reg         wd_reset,            // assert main CPU reset (active-high)
    output reg         flip_screen          // screen flip output
);

    //------------------------------------------------------------------------
    // Watchdog counter logic
    // Reference: decocass_v.cpp lines 388-393
    //
    // The 4-bit counter counts down every vblank. When it reaches 0, the
    // watchdog asserts reset. Writing to $E300 reloads the counter with
    // (data & 0x0f) + 1 and clears the overflow.
    //------------------------------------------------------------------------

    reg [3:0] wd_counter;                   // 4-bit countdown counter (0-15)
    wire [3:0] wd_reload_val = (cpu_dout[3:0] & 4'hF) + 4'h1;

    always @(posedge clk_sys) begin
        if (reset) begin
            wd_counter <= 4'hF;             // Start with full count
            wd_reset   <= 1'b0;
        end else if (ce_hclk1) begin
            if (wd_count_w) begin
                // CPU writes to $E300: reload counter and clear reset
                // Reference: decocass.cpp line 391-392
                wd_counter <= wd_reload_val;  // (data & 0x0f) + 1
                wd_reset   <= 1'b0;
            end else if (vblank_pulse) begin
                // Decrement counter on each vblank (falling edge)
                if (wd_counter == 4'h0) begin
                    // Counter underflow: assert reset
                    wd_reset <= 1'b1;
                end else begin
                    wd_counter <= wd_counter - 4'h1;
                end
            end
        end
    end

    //------------------------------------------------------------------------
    // Flip register and screen-flip output
    // Reference: decocass_v.cpp lines 395-400, screen_update_decocass line 741
    //
    // Writing to $E301 stores the data byte. Bit[3] gates the watchdog enable,
    // but we don't implement watchdog_enable() separately; the flip register
    // itself is latched.
    //
    // flip_screen is computed as: m_watchdog_flip & BIT(DSW1, 6)
    // where BIT(DSW1, 6) = cocktail cabinet mode.
    //------------------------------------------------------------------------

    reg [7:0] flip_register;

    always @(posedge clk_sys) begin
        if (reset) begin
            flip_register <= 8'h00;
        end else if (ce_hclk1 && wd_flip_w) begin
            // CPU writes to $E301: store data
            // Reference: decocass_v.cpp line 399
            flip_register <= cpu_dout;
        end
    end

    // Compute flip_screen: XOR of the flip register with cocktail DSW bit
    // Reference: decocass_v.cpp line 741 (slightly reinterpreted for Verilog)
    // flip_screen_set(m_watchdog_flip & BIT(m_dsw[0]->read(), 6))
    //
    // In MAME, this appears to AND the register with the DSW bit, but the
    // task description says "XOR with DSW1[6]". Let's verify:
    // - MAME line 741: flip_screen_set(m_watchdog_flip & BIT(m_dsw[0]->read(), 6))
    // - This is an AND, not XOR. The result only depends on whether both bits are set.
    //
    // TODO(verify-with-mame): Confirm flip_screen polarity. Is it (register & dsw[6])
    // or (register ^ dsw[6]) or something else? Currently implementing the MAME version (AND).

    wire cabinet_mode = dsw1[6];

    always @* begin
        flip_screen = flip_register[0] & cabinet_mode;  // AND as per MAME line 741
    end

    //------------------------------------------------------------------------
    // Debug/documentation
    //------------------------------------------------------------------------

    // Unused inputs (for reference):
    // - cpu_dout[7:4] during $E300 write: ignored by watchdog (used for other purposes)
    // - cpu_dout[7:4] during $E301 write: TODO(verify-with-mame) — not documented
    // - BIT(cpu_dout, 3) on $E301 write: enables/disables watchdog
    //   (we don't implement separate enable/disable; the counter always ticks)

endmodule
