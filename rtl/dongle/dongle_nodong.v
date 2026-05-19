/*============================================================================
  Dongle "nodong" (cflyball, etc.) — pass-through of MCU host-bus registers.

  Per MAME `decocass_nodong_r` (decocass_m.cpp:1026-1058):
    offset & 1 == 0 → upi41_master_r(0) = MCU DBBOUT
    offset & 1 == 1 → upi41_master_r(1) = MCU DBBSTS

  2026-05-18: takes MCU host-bus registers (NOT P2 outputs — the old
  `mcu_status_low` wiring was incorrect per MAME).
============================================================================*/

`timescale 1 ps / 1 ps

module dongle_nodong (
    input  wire [7:0]  mcu_dbb_dout,
    input  wire [7:0]  mcu_dbb_sts,
    input  wire [7:0]  cpu_addr_lo,
    output wire [7:0]  cpu_din_full
);
    assign cpu_din_full = cpu_addr_lo[0] ? mcu_dbb_sts : mcu_dbb_dout;
endmodule
