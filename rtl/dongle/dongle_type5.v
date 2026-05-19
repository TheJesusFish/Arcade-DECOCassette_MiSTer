/*============================================================================
  Type 5 Dongle — Fixed Value 0x55 Return (Task 21)

  Implements the Type 5 dongle used in games like Boulder Dash, Flyball,
  Disco No. 1, and Pepper II ICE.

  The Type 5 dongle is essentially a NOP dongle: it returns a fixed value
  0x55 after a latch is activated. All games using this type do their own
  decryption logic, so this dongle is trivial.

  Reference: decocass_m.cpp lines 950-1016

  State variables (from decocass_m.cpp):
    - m_type5_latch  : Enable latch (set when cpu_dout[7:4] == 0xC on odd-address write)

  Write behavior (decocass_m.cpp:992-1016):
    - Odd address ($E5x1): Set latch
      * If latch == 1: No-op (line 998)
      * If cpu_dout[7:4] == 0xC0: Set latch = 1 (line 1002)
      * Otherwise: Forward to MCU (line 1015)
    - Even address ($E5x0): Handled by MCU passthrough

  Read behavior (decocass_m.cpp:950-990):
    - Odd address ($E5x1): Return MCU status (line 958)
    - Even address ($E5x0): Return 0x55 if latch == 1 (line 971)
      * Otherwise: Return MCU data or open-bus (lines 978-985)

============================================================================*/

`timescale 1 ps / 1 ps

module dongle_type5 (
    input  wire        clk_sys,
    input  wire        ce_hclk4,
    input  wire        reset,

    input  wire        cpu_re,
    input  wire        cpu_we,
    input  wire [7:0]  cpu_addr_lo,
    input  wire [7:0]  cpu_dout,
    input  wire [7:0]  mcu_dbb_dout,
    input  wire [7:0]  mcu_dbb_sts,
    output reg  [7:0]  cpu_din_full         // 2026-05-18: 8-bit per MAME
);

    //------------------------------------------------------------------------
    // Internal state (synchronous updates)
    //------------------------------------------------------------------------
    reg m_type5_latch;   // Enable latch (set on 0xCx write to odd address)

    //------------------------------------------------------------------------
    // Synchronous state updates
    // (decocass_m.cpp:992-1016, decocass_type5_w)
    //------------------------------------------------------------------------
    always @(posedge clk_sys) begin
        if (reset) begin
            m_type5_latch <= 1'b0;
        end
        else if (ce_hclk4 && cpu_we) begin
            // Write handler (decocass_m.cpp:992-1016)
            if (cpu_addr_lo[0] == 1'b1) begin  // Odd address write ($E5x1)
                // Check if initialization byte (0xC0–0xCF)
                if ((cpu_dout[7:4] == 4'hC)) begin
                    // Activate latch (line 1002-1003)
                    m_type5_latch <= 1'b1;
                end
                // If latch == 1, the write is ignored (line 996-1000)
                // Otherwise, forward to MCU
            end
            // Even address writes (line 1005-1012) pass to MCU or are ignored if latch == 1
        end
    end

    //------------------------------------------------------------------------
    // Output data mux: Fixed 0x55 vs. MCU passthrough
    // (decocass_m.cpp:950-990)
    //------------------------------------------------------------------------
    always @(*) begin
        if (cpu_addr_lo[0] == 1'b1) begin
            cpu_din_full = mcu_dbb_sts;
        end else begin
            if (m_type5_latch) begin
                cpu_din_full = 8'h55;
            end else begin
                cpu_din_full = mcu_dbb_dout;
            end
        end
    end

endmodule
