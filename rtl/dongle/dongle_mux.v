/*============================================================================
  Dongle Multiplexer — Task 18

  Routes $E5xx read cycles to the appropriate dongle type based on the
  3-bit dongle_type input (set per-game by MRA metadata byte).

  2026-05-18 — REWORKED interface to match MAME:
    - Each dongle returns 8-bit `cpu_din_full` (was 4-bit `cpu_din_low4`).
    - Data input is `mcu_dbb_dout` (host DBBOUT, 8-bit) and `mcu_dbb_sts`
      (host DBBSTS, 8-bit), per MAME `upi41_master_r(0)/(1)`.

  Note: the wrapper currently uses `mcu_tape_iface`'s `latched_host_dout`
  path for the cpu_din going to BIOS, BYPASSING this dongle output. That's
  fine for the boot-logo phase. To restore dongle transforms for cassette
  game loading later, change the wrapper's cpu_din source from
  `mcu_tape_iface.cpu_din` to use `dongle_din_full` instead.
============================================================================*/

`timescale 1 ps / 1 ps

module dongle_mux (
    input  wire        clk_sys,
    input  wire        ce_hclk4,
    input  wire        reset,

    input  wire [2:0]  dongle_type,
    input  wire [7:0]  game_id,    // 2026-05-30: 8-bit = DECO release number (type1 case key)
    input  wire [3:0]  swap_mode,

    input  wire        cpu_re,
    input  wire        cpu_we,
    input  wire [7:0]  cpu_addr_lo,
    input  wire [7:0]  cpu_dout,
    output reg  [7:0]  cpu_din_full,

    output reg  [11:0] dprom_addr,
    input  wire [7:0]  dprom_q,

    // MCU host-bus registers (DBBOUT/DBBSTS) per MAME `upi41_master_r(0/1)`
    input  wire [7:0]  mcu_dbb_dout,
    input  wire [7:0]  mcu_dbb_sts,

    // Type 2 uses P2[2], Type 3 uses P2[0] for game-specific encryption bits
    input  wire        mcu_status_d2,
    input  wire        mcu_status_d0
);

    wire [7:0] type1_prom_addr;
    wire [7:0] type1_q;
    dongle_type1 type1_inst (
        .clk_sys (clk_sys), .ce_hclk4 (ce_hclk4), .reset (reset),
        .cpu_re (cpu_re), .cpu_we (cpu_we),
        .cpu_addr_lo (cpu_addr_lo), .cpu_dout (cpu_dout),
        .cpu_din_full (type1_q),
        .game_id (game_id),
        .mcu_dbb_dout (mcu_dbb_dout), .mcu_dbb_sts (mcu_dbb_sts),
        .prom_addr (type1_prom_addr), .prom_q (dprom_q)
    );

    wire [8:0] type2_prom_addr;
    wire [7:0] type2_q;
    dongle_type2 type2_inst (
        .clk_sys (clk_sys), .ce_hclk4 (ce_hclk4), .reset (reset),
        .cpu_re (cpu_re), .cpu_we (cpu_we),
        .cpu_addr_lo (cpu_addr_lo), .cpu_dout (cpu_dout),
        .cpu_din_full (type2_q),
        .mcu_status_d2 (mcu_status_d2),
        .mcu_dbb_dout (mcu_dbb_dout), .mcu_dbb_sts (mcu_dbb_sts),
        .prom_addr (type2_prom_addr), .prom_q (dprom_q)
    );

    wire [11:0] type3_prom_addr;
    wire [7:0]  type3_q;
    dongle_type3 type3_inst (
        .clk_sys (clk_sys), .ce_hclk4 (ce_hclk4), .reset (reset),
        .cpu_re (cpu_re), .cpu_we (cpu_we),
        .cpu_addr_lo (cpu_addr_lo), .cpu_dout (cpu_dout),
        .cpu_din_full (type3_q),
        .swap_mode (swap_mode), .mcu_status_d0 (mcu_status_d0),
        .mcu_dbb_dout (mcu_dbb_dout), .mcu_dbb_sts (mcu_dbb_sts),
        .prom_addr (type3_prom_addr), .prom_q (dprom_q)
    );

    wire [14:0] type4_prom_addr;
    wire [7:0]  type4_q;
    dongle_type4 type4_inst (
        .clk_sys (clk_sys), .ce_hclk4 (ce_hclk4), .reset (reset),
        .cpu_re (cpu_re), .cpu_we (cpu_we),
        .cpu_addr_lo (cpu_addr_lo), .cpu_dout (cpu_dout),
        .cpu_din_full (type4_q),
        .mcu_dbb_dout (mcu_dbb_dout), .mcu_dbb_sts (mcu_dbb_sts),
        .prom_addr (type4_prom_addr), .prom_q (dprom_q)
    );

    wire [7:0] type5_q;
    dongle_type5 type5_inst (
        .clk_sys (clk_sys), .ce_hclk4 (ce_hclk4), .reset (reset),
        .cpu_re (cpu_re), .cpu_we (cpu_we),
        .cpu_addr_lo (cpu_addr_lo), .cpu_dout (cpu_dout),
        .mcu_dbb_dout (mcu_dbb_dout), .mcu_dbb_sts (mcu_dbb_sts),
        .cpu_din_full (type5_q)
    );

    wire [7:0] nodong_q;
    dongle_nodong nodong_inst (
        .mcu_dbb_dout (mcu_dbb_dout), .mcu_dbb_sts (mcu_dbb_sts),
        .cpu_addr_lo (cpu_addr_lo),
        .cpu_din_full (nodong_q)
    );

    always @(*) begin
        case (dongle_type)
            3'b001:  cpu_din_full = type1_q;
            3'b010:  cpu_din_full = type2_q;
            3'b011:  cpu_din_full = type3_q;
            3'b100:  cpu_din_full = type4_q;
            3'b101:  cpu_din_full = type5_q;
            3'b110:  cpu_din_full = nodong_q;
            default: cpu_din_full = 8'hFF;
        endcase
    end

    always @(*) begin
        case (dongle_type)
            3'b001:  dprom_addr = {4'b0000, type1_prom_addr};
            3'b010:  dprom_addr = {3'b000,  type2_prom_addr};
            3'b011:  dprom_addr = type3_prom_addr;
            3'b100:  dprom_addr = type4_prom_addr[11:0];
            3'b101:  dprom_addr = 12'h000;
            3'b110:  dprom_addr = 12'h000;
            default: dprom_addr = 12'h000;
        endcase
    end

endmodule
