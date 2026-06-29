// DECO Cassette — Missile layer renderer
// MISSILES-IMPL-2026-06-28: real implementation; REPLACES the non-functional stub that was neutered
// 2026-06-11 (mis_pair_idx stuck at 0, only y_lower ever fetched, x/y_upper/x_lower uninitialized →
// painted garbage → forced dark). Old stub recoverable via git. Structure mirrors the WORKING
// video_sprites.v (32-step scan FSM → latch all positions → per-pixel compare).
//
// MAME decocass_v.cpp:572-617 draw_missiles. missile_ram == m_colorram, interleave 0x20.
// 16 missiles = 8 pairs (i=0..7), offs = i*4*0x20 = i*0x80:
//   lower: y = ram[offs+0x00], x = ram[offs+0x40]
//   upper: y = ram[offs+0x20], x = ram[offs+0x60]
//   sx = 255 - x ;  sy = 255 - y - missile_y_adjust(=1)  ;  dot is 4px wide x 1px tall
//   lower pen = (color_missiles & 7) | 8 ;  upper pen = ((color_missiles>>4) & 7) | 8   (= pens 8..15)
//   priority: lower |= 1<<2, upper |= 1<<3 (upper drawn after lower → wins on overlap)

`timescale 1 ps / 1 ps

module video_missiles (
    input  wire        clk_sys,
    input  wire        ce_pix,

    input  wire [8:0]  hcnt,
    input  wire [8:0]  vcnt,

    input  wire [7:0]  color_missiles,   // $E302 latch (already masked & 0x77 upstream)

    // CPU write mirror — missile descriptors live in colorram
    input  wire        cpu_we_mis,
    input  wire [9:0]  cpu_mis_addr,
    input  wire [7:0]  cpu_mis_dout,

    output reg  [4:0]  mis_pen,
    output reg         mis_priority
);

    localparam [7:0] MIS_X_ADJ = 8'd0;   // tune after first build if missiles land 1px off in X
    localparam [7:0] MIS_Y_ADJ = 8'd0;   // ...or 1 line off in Y

    // ---- Descriptor mirror (copy of colorram; CPU colorram writes mirrored in) ----
    reg  [9:0] dsc_addr;
    wire [7:0] dsc_q;
    dpram #(.address_width(10), .data_width(8)) missile_desc_ram_inst (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_mis),
        .address_a(cpu_mis_addr), .data_a(cpu_mis_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(1'b1), .wren_b(1'b0),
        .address_b(dsc_addr), .data_b(8'b0), .q_b(dsc_q)
    );

    // ---- 32-step scan → latch all 16 missile positions (mirrors video_sprites scan FSM) ----
    //   byte 0(+0x00)=y_lower  1(+0x20)=y_upper  2(+0x40)=x_lower  3(+0x60)=x_upper
    reg  [7:0] sx_lo [0:7];
    reg  [7:0] sy_lo [0:7];
    reg  [7:0] sx_up [0:7];
    reg  [7:0] sy_up [0:7];

    reg  [4:0] scan, scan_d;
    wire [2:0] scan_pair = scan[4:2];
    wire [1:0] scan_byte = scan[1:0];
    wire [9:0] scan_addr = {scan_pair, scan_byte, 5'b00000};  // pair*0x80 + byte*0x20

    always @(posedge clk_sys) begin
        if (ce_pix) begin
            // latch the byte requested last cycle (indexed by scan_d); 255-x for X, 254-y(=255-y-1) for Y
            case (scan_d[1:0])
                2'd0: sy_lo[scan_d[4:2]] <= 8'd254 - dsc_q + MIS_Y_ADJ;
                2'd1: sy_up[scan_d[4:2]] <= 8'd254 - dsc_q + MIS_Y_ADJ;
                2'd2: sx_lo[scan_d[4:2]] <= 8'd255 - dsc_q + MIS_X_ADJ;
                2'd3: sx_up[scan_d[4:2]] <= 8'd255 - dsc_q + MIS_X_ADJ;
            endcase
            dsc_addr <= scan_addr;
            scan_d   <= scan;
            scan     <= scan + 1'b1;
        end
    end

    // ---- per-pixel hit: 4px wide x 1px tall, 8-bit position math (auto +256 wrap, like sprites) ----
    integer k;
    reg       hit_lo, hit_up;
    reg [7:0] dxl, dyl, dxu, dyu;
    always @(*) begin
        hit_lo = 1'b0; hit_up = 1'b0;
        for (k = 0; k < 8; k = k + 1) begin
            dxl = hcnt[7:0] - sx_lo[k];  dyl = vcnt[7:0] - sy_lo[k];
            if ((dxl < 8'd4) && (dyl == 8'd0)) hit_lo = 1'b1;
            dxu = hcnt[7:0] - sx_up[k];  dyu = vcnt[7:0] - sy_up[k];
            if ((dxu < 8'd4) && (dyu == 8'd0)) hit_up = 1'b1;
        end
    end

    // pens 8..15: lower=(color&7)|8, upper=((color>>4)&7)|8 (color_missiles is stable per frame)
    wire [4:0] pen_lo = {2'b01, color_missiles[2:0]};
    wire [4:0] pen_up = {2'b01, color_missiles[6:4]};

    // ---- output: 2 ce_pix stages to match video_sprites' hcnt→pen latency (keeps layers aligned) ----
    reg hit_lo_1, hit_up_1;
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            hit_lo_1 <= hit_lo;
            hit_up_1 <= hit_up;
            // upper drawn after lower in MAME → upper wins on overlap
            if (hit_up_1) begin
                mis_pen      <= pen_up;
                mis_priority <= 1'b1;
            end else if (hit_lo_1) begin
                mis_pen      <= pen_lo;
                mis_priority <= 1'b1;
            end else begin
                mis_pen      <= 5'b00000;
                mis_priority <= 1'b0;
            end
        end
    end

endmodule
