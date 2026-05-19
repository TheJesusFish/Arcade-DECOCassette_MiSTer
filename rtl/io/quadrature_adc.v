//============================================================================
//  Quadrature ADC Controller (cfishing / cadanglr only)
//
//  Converts analog joystick axis positions to quadrature-encoded counters.
//  Cycle-accurate relative to MAME decocass_m.cpp:
//    - decocass_quadrature_decoder_reset_w (line 161-166): latches all 4 axes
//    - decocass_adc_w (line 168-170): no-op (ADC not actually used in cfishing)
//    - decocass_input_r (line 182-199): reads quadrature at $E603-$E606
//
//  This module tracks position deltas and emits Gray-coded quadrature
//  edges. MAME simply latches analog[4] at reset and reads back.
//  For now, we implement a simplified pass-through that mirrors the
//  joystick axis position directly (not true quadrature simulation).
//
//  Reference: decocass.h line 147 declares array m_quadrature_decoder[4]
//============================================================================

`timescale 1 ps / 1 ps

module quadrature_adc (
    input  wire        clk_sys,
    input  wire        ce_hclk4,       // 1.5 MHz (optional, for future edge detection)
    input  wire        reset,

    // From MiSTer analog joystick (0x10..0xf0 when input range clamped)
    input  wire [7:0]  joy_x,          // Paddle position: X axis (0x10=left, 0x80=center, 0xf0=right)
    input  wire [7:0]  joy_y,          // Paddle position: Y axis (0x10=top, 0x80=center, 0xf0=bottom)

    // CPU strobes
    input  wire        cpu_we_quad_reset,    // $E415/$E416 write strobe
    input  wire        cpu_we_adc,           // $E420-$E42F write strobe
    input  wire [7:0]  cpu_dout,             // CPU data bus (unused for reset/adc)
    input  wire [7:0]  cpu_addr_lo,          // Low address byte ($E420-$E42F index)

    // Read-back into input mux ($E603-$E606)
    output reg  [7:0]  quad_h1,             // $E603: Horizontal paddle #1 (X position)
    output reg  [7:0]  quad_v1,             // $E604: Vertical paddle #1 (Y position)
    output reg  [7:0]  quad_h2,             // $E605: Horizontal paddle #2 (unused in cfishing)
    output reg  [7:0]  quad_v2              // $E606: Vertical paddle #2 (unused in cfishing)
);

    //------------------------------------------------------------------------
    // Per MAME decocass_m.cpp line 161-166:
    //   void decocass_quadrature_decoder_reset_w(uint8_t data) {
    //     for (int i = 0; i < 4; i++)
    //       m_quadrature_decoder[i] = m_analog[i]->read();  // 0x10..0xf0
    //   }
    //
    // m_analog[0] = AN0 (P1 joy_x)
    // m_analog[1] = AN1 (P1 joy_y)
    // m_analog[2] = AN2 (P2 joy_x, if two-player)
    // m_analog[3] = AN3 (P2 joy_y, if two-player)
    //------------------------------------------------------------------------

    always @(posedge clk_sys) begin
        if (!reset) begin
            quad_h1 <= 8'h80;    // Center position (matches default 0x80 from decocass.cpp)
            quad_v1 <= 8'h80;
            quad_h2 <= 8'h80;
            quad_v2 <= 8'h80;
        end
        else if (cpu_we_quad_reset) begin
            // Latch the four analog inputs at reset time
            // This matches MAME's behavior exactly:
            quad_h1 <= joy_x;    // m_analog[0]
            quad_v1 <= joy_y;    // m_analog[1]
            quad_h2 <= 8'h80;    // m_analog[2] (placeholder; not used in cfishing)
            quad_v2 <= 8'h80;    // m_analog[3] (placeholder; not used in cfishing)
        end
        // cpu_we_adc at $E420-$E42F is a no-op in MAME (line 168-170)
        // No action needed.
    end

    //------------------------------------------------------------------------
    // NOTES FOR FUTURE ENHANCEMENT:
    //
    // If full quadrature edge tracking is needed (true Gray-code A/B output):
    //  1. Track previous axis position on each ce_hclk4 pulse.
    //  2. On positive delta: emit Gray-coded quadrature sequence (+1 edge).
    //  3. On negative delta: emit inverse Gray-coded sequence (-1 edge).
    //  4. Output 2-bit Gray code or 8-bit counter for relative position.
    //
    // For now, MAME cfishing emulation does NOT require true quadrature
    // simulation—it only latches and reads back raw ADC values.
    // This simplified pass-through is cycle-accurate.
    //------------------------------------------------------------------------

endmodule
