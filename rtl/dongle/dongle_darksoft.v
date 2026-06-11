/*============================================================================
  Darksoft multigame dongle  (MAME: decocass_darksoft_state, decocass_m.cpp:1157-1187)

  A 20-bit auto-incrementing counter into a 1 MB dongle ROM. The 6502:
    - WRITE $E5x0/1  -> address = data            (low byte; upper 12 bits cleared)
    - READ  $E500    -> data = donglerom[address]; address += 1
    - READ  $E501    -> data = donglerom[address]; address += 0x100
    - READ  $E502+    -> open bus ($FF)

  Storage (prom_q @ prom_addr) is provided by the wrapper — a BRAM for the
  Stage-1 menu test, SDRAM/DDR for the full 1 MB later. The read returns the
  byte at the CURRENT address; the increment lands on the next ce_hclk4 edge,
  so the 6502 (which samples cpu_din_full combinationally during its slow
  ce_main read) always sees the pre-increment byte — matching MAME order.

  Interface mirrors the other dongle_type* modules so it drops into dongle_mux.
============================================================================*/

`timescale 1 ps / 1 ps

module dongle_darksoft (
    input  wire        clk_sys,
    input  wire        ce_hclk4,
    input  wire        reset,

    input  wire        cpu_re,        // $E5xx read  access strobe
    input  wire        cpu_we,        // $E5xx write access strobe
    input  wire [7:0]  cpu_addr_lo,   // low address byte (the MAME "offset")
    input  wire [7:0]  cpu_dout,      // data from 6502 (writes)
    output reg  [7:0]  cpu_din_full,  // data to 6502

    output wire [19:0] prom_addr,     // 20-bit dongle ROM address (1 MB)
    input  wire [7:0]  prom_q,        // dongle ROM byte at prom_addr

    // 8041 host regs — unused by Darksoft reads, kept for dongle_mux interface parity
    input  wire [7:0]  mcu_dbb_dout,
    input  wire [7:0]  mcu_dbb_sts
);

    reg [19:0] address;
    assign prom_addr = address;

    // MAME offsets are exact 0 / 1 within the $E5xx window
    wire off0 = (cpu_addr_lo == 8'h00);   // $E500
    wire off1 = (cpu_addr_lo == 8'h01);   // $E501

    // Read data: $E500/$E501 stream the ROM, everything else is open bus.
    always @(*) begin
        if (off0 || off1) cpu_din_full = prom_q;
        else              cpu_din_full = 8'hFF;
    end

    // Address register: write loads the low byte (clears the rest);
    // reads auto-increment (+1 at $E500, +0x100 at $E501).
    always @(posedge clk_sys) begin
        if (reset) begin
            address <= 20'd0;
        end else if (ce_hclk4) begin
            if (cpu_we && (off0 || off1))
                address <= {12'd0, cpu_dout};        // m_address = data
            else if (cpu_re && off0)
                address <= address + 20'd1;          // m_address++
            else if (cpu_re && off1)
                address <= address + 20'h00100;      // m_address += 0x100
        end
    end

endmodule
