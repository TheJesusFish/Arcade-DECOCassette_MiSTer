/*============================================================================
  Type 2 Dongle — PROM with D2 Latch (Task 21)

  Implements the Type 2 dongle used in games like Grapplop, Clucky Pot,
  Crazy Proball, Night Star, etc.

  The Type 2 dongle performs:
  1. A 256-byte PROM lookup (8-bit address from cpu_addr_lo)
  2. A D2 latch that selects PROM page (bits 8:8 of address)
  3. An enable latch (xx_latch) that gates PROM access vs. MCU passthrough

  Reference: decocass_m.cpp lines 541-602

  State variables (from decocass_m.cpp):
    - m_type2_promaddr  : PROM address (8 bits) from cpu_addr_lo on even-address write
    - m_type2_d2_latch  : D2 status latch (bit 2 of initialization write)
    - m_type2_xx_latch  : Enable latch (set when cpu_dout[7:4] == 0xC on odd-address write)

  Write behavior (decocass_m.cpp:569-602):
    - Odd address ($E5x1): Write initialization/D2 latch
      * If xx_latch == 1: (no-op)
      * If cpu_dout[7:4] == 0xC0: Set xx_latch = 1, D2 latch = (cpu_dout[2])
      * Otherwise: Forward to MCU
    - Even address ($E5x0): Write PROM address
      * If xx_latch == 1: Set m_type2_promaddr = cpu_dout
      * Otherwise: Forward to MCU

  Read behavior (decocass_m.cpp:541-567):
    - Odd address ($E5x1): Return PROM byte if xx_latch == 1, else MCU status
    - Even address ($E5x0): Return 0xFF (floating) if xx_latch == 1, else MCU data
    - PROM address: {D2_latch, promaddr[7:0]}

============================================================================*/

`timescale 1 ps / 1 ps

module dongle_type2 (
    input  wire        clk_sys,
    input  wire        ce_hclk4,
    input  wire        reset,

    input  wire        cpu_re,
    input  wire        cpu_we,
    input  wire [7:0]  cpu_addr_lo,
    input  wire [7:0]  cpu_dout,
    output reg  [7:0]  cpu_din_full,        // 2026-05-18: 8-bit per MAME

    input  wire        mcu_status_d2,
    input  wire [7:0]  mcu_dbb_dout,        // MCU DBBOUT
    input  wire [7:0]  mcu_dbb_sts,         // MCU DBBSTS

    output wire [8:0]  prom_addr,
    input  wire [7:0]  prom_q
);

    //------------------------------------------------------------------------
    // Internal state (synchronous updates)
    //------------------------------------------------------------------------
    reg [7:0] m_type2_promaddr;   // PROM address register (8 bits)
    reg        m_type2_d2_latch;   // D2 latch (page select)
    reg        m_type2_xx_latch;   // Enable latch (gates PROM vs. MCU passthrough)

    //------------------------------------------------------------------------
    // Synchronous state updates
    // (decocass_m.cpp:569-602, decocass_type2_w)
    //------------------------------------------------------------------------
    always @(posedge clk_sys) begin
        if (reset) begin
            m_type2_promaddr  <= 8'h00;
            m_type2_d2_latch  <= 1'b0;
            m_type2_xx_latch  <= 1'b0;
        end
        else if (ce_hclk4 && cpu_we) begin
            // Write handler (decocass_m.cpp:569-602)
            if (cpu_addr_lo[0] == 1'b1) begin  // Odd address write ($E5x1)
                // Check if initialization byte (0xC0–0xCF)
                if ((cpu_dout[7:4] == 4'hC)) begin
                    // Activate PROM latch and capture D2 status bit
                    // (decocass_m.cpp:590-594)
                    m_type2_xx_latch <= 1'b1;
                    m_type2_d2_latch <= (cpu_dout[2]) ? 1'b1 : 1'b0;
                end
                // If xx_latch == 1, write to odd address is ignored (line 575)
            end
            else if (cpu_addr_lo[0] == 1'b0) begin  // Even address write ($E5x0)
                // If xx_latch == 1, latch the PROM address (line 579)
                if (m_type2_xx_latch == 1'b1) begin
                    m_type2_promaddr <= cpu_dout;
                end
            end
        end
    end

    //------------------------------------------------------------------------
    // PROM address generation: {D2_latch, promaddr[7:0]}
    // (decocass_m.cpp:549)
    //------------------------------------------------------------------------
    assign prom_addr = {m_type2_d2_latch, m_type2_promaddr};

    //------------------------------------------------------------------------
    // Output data mux: PROM vs. MCU passthrough
    // (decocass_m.cpp:541-567)
    //------------------------------------------------------------------------
    always @(*) begin
        if (m_type2_xx_latch == 1'b1) begin
            if (cpu_addr_lo[0] == 1'b1) begin
                cpu_din_full = prom_q;
            end else begin
                cpu_din_full = 8'hFF;
            end
        end else begin
            cpu_din_full = cpu_addr_lo[0] ? mcu_dbb_sts : mcu_dbb_dout;
        end
    end

endmodule
