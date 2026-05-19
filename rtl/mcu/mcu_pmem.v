/*============================================================================
  MCU Program Memory (1 KB) — dual-port BRAM for UPI41 core

  Port A: Write-only, driven by rom_loader (task 25)
  Port B: Read-only, driven by upi41_core program memory controller

  i8041 ROM size: 1024 bytes (10-bit address)
  ============================================================================*/

`timescale 1 ps / 1 ps

module mcu_pmem (
    input  wire         clk,
    // Port A: write-only (rom_loader)
    input  wire         we_a,
    input  wire [9:0]   addr_a,
    input  wire [7:0]   din_a,
    // Port B: read-only (upi41_core.pmem_addr_o)
    input  wire [10:0]  addr_b,      // upi41_core provides 11 bits, we use [9:0]
    output reg [7:0]    dout_b
);

    localparam RAM_DEPTH = 1024;      // 2^10 bytes

    reg [7:0] mem [0:RAM_DEPTH-1];

    // Port A: synchronous write
    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;
    end

    // Port B: synchronous read (combinational output registered on next clock)
    always @(posedge clk) begin
        dout_b <= mem[addr_b[9:0]];
    end

endmodule
