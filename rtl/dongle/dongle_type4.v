/*============================================================================
  Type 4 Dongle — 15-bit Counter + 32KB PROM (Task 21)

  Implements the Type 4 dongle used in games like Scrum Try and Oozumou
  (The Grand Sumo).

  The Type 4 dongle performs:
  1. A 15-bit counter (m_type4_ctrs, range 0x0000–0x7FFF)
  2. A 32KB PROM (32K = 0x8000 bytes) indexed by the counter
  3. Auto-increment of the counter on each PROM read
  4. An enable latch (latch) that gates PROM vs. MCU passthrough

  Reference: decocass_m.cpp lines 866-939

  State variables (from decocass_m.cpp):
    - m_type4_ctrs   : 15-bit counter (0–0x7FFF, wraps at 0x8000)
    - m_type4_latch  : Enable latch (set when cpu_dout[7:4] == 0xC on odd-address write)

  Write behavior (decocass_m.cpp:912-939):
    - Odd address ($E5x1): Load MSB of counter
      * If latch == 1: Set m_type4_ctrs[14:8] = {cpu_dout[6:0], 1'b0} (7 bits)
      * If cpu_dout[7:4] == 0xC0: Set latch = 1
      * Otherwise: Forward to MCU
    - Even address ($E5x0): Load LSB of counter
      * If latch == 1: Set m_type4_ctrs[7:0] = cpu_dout
      * Otherwise: Forward to MCU

  Read behavior (decocass_m.cpp:866-910):
    - Odd address ($E5x1): Return MCU status if latch == 1, else 0xFF
    - Even address ($E5x0): Return PROM byte if latch == 1 (auto-increment after)
      * Counter increments after read: (m_type4_ctrs + 1) & 0x7FFF (line 891)
    - PROM address: 15 bits {counter[14:0]}

============================================================================*/

`timescale 1 ps / 1 ps

module dongle_type4 (
    input  wire        clk_sys,
    input  wire        ce_hclk4,
    input  wire        reset,

    input  wire        cpu_re,
    input  wire        cpu_we,
    input  wire [7:0]  cpu_addr_lo,
    input  wire [7:0]  cpu_dout,
    output reg  [7:0]  cpu_din_full,        // 2026-05-18: 8-bit per MAME

    input  wire [7:0]  mcu_dbb_dout,
    input  wire [7:0]  mcu_dbb_sts,

    output wire [14:0] prom_addr,
    input  wire [7:0]  prom_q,

    // DONGLE-WE-CONSUMED-2026-06-27: high when this dongle consumes a CPU write (MAME type4_w RETURNs
    // on every write while latch=1 — counter MSB/LSB load — and does NOT forward to the 8041). The wrapper
    // uses this to suppress the 8041 write so the counter-load bytes don't hit it as a spurious DATA/CMND.
    output wire        we_consumed
);

    //------------------------------------------------------------------------
    // Internal state (synchronous updates)
    //------------------------------------------------------------------------
    reg [14:0] m_type4_ctrs;     // 15-bit counter (range 0–0x7FFF)
    reg        m_type4_latch;    // Enable latch (gates PROM vs. MCU passthrough)

    //------------------------------------------------------------------------
    // Synchronous state updates
    // (decocass_m.cpp:912-939, decocass_type4_w)
    //------------------------------------------------------------------------
    always @(posedge clk_sys) begin
        if (reset) begin
            m_type4_ctrs   <= 15'h0000;
            m_type4_latch  <= 1'b0;
        end
        else if (ce_hclk4) begin
            // Write handler (decocass_m.cpp:912-939)
            if (cpu_we) begin
                if (cpu_addr_lo[0] == 1'b1) begin  // Odd address write ($E5x1)
                    if (m_type4_latch == 1'b1) begin
                        // Load MSB: counter[14:8] = {cpu_dout[6:0], 1'b0}
                        // (decocass_m.cpp:918, note the mask is 0x7f)
                        m_type4_ctrs[14:8] <= {cpu_dout[6:0]};
                    end
                    else if ((cpu_dout[7:4] == 4'hC)) begin
                        // Activation sequence (line 923-925)
                        m_type4_latch <= 1'b1;
                    end
                end
                else if (cpu_addr_lo[0] == 1'b0) begin  // Even address write ($E5x0)
                    if (m_type4_latch == 1'b1) begin
                        // Load LSB: counter[7:0] = cpu_dout
                        // (decocass_m.cpp:932)
                        m_type4_ctrs[7:0] <= cpu_dout;
                    end
                end
            end

            // Read handler: auto-increment counter on even-address read
            // (decocass_m.cpp:884-892)
            if (cpu_re) begin
                if (cpu_addr_lo[0] == 1'b0) begin  // Even address read ($E5x0)
                    if (m_type4_latch == 1'b1) begin
                        // Auto-increment counter after read (line 891)
                        // Wrap at 0x8000 (15 bits max)
                        m_type4_ctrs <= (m_type4_ctrs + 15'h0001) & 15'h7FFF;
                    end
                end
            end
        end
    end

    //------------------------------------------------------------------------
    // PROM address generation: 15-bit counter
    // (decocass_m.cpp:887)
    //------------------------------------------------------------------------
    assign prom_addr = m_type4_ctrs;

    // When latch is set, every $E5x0/$E5x1 write is a counter load → MAME returns, no 8041 forward.
    // (The latch-SET write itself has latch still 0 this cycle, so it correctly forwards to the 8041.)
    assign we_consumed = m_type4_latch;

    //------------------------------------------------------------------------
    // Output data mux: PROM vs. MCU passthrough
    // (decocass_m.cpp:866-910)
    //------------------------------------------------------------------------
    always @(*) begin
        if (cpu_addr_lo[0] == 1'b1) begin
            cpu_din_full = mcu_dbb_sts;
        end else begin
            cpu_din_full = m_type4_latch ? prom_q : mcu_dbb_dout;
        end
    end

endmodule
