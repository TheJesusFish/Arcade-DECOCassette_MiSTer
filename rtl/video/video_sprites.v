// DECO Cassette — Sprite layer renderer  (REWRITE 2026-06-10 — the prior version was a non-functional stub:
// empty gfx BRAMs, descriptor code/X/Y never read, no slot iteration → sprites invisible in every game.)
//
// 8 sprites, 16×16, 3bpp, descriptors interleaved in fgvideoram, graphics shared with the chars in charram.
// References:
//   MAME decocass_v.cpp:524-569  draw_sprites
//   MAME decocass.cpp:950-959     spritelayout (16,16, 256, planes=3, the offsets below)
//
// DESCRIPTORS (in fgvideoram — mirrored here via the CPU write port). 8 slots, base offs = 28*0x20 = 0x380,
// stepping DOWN by 4*0x20 = 0x80 each slot (slot 0 = 0x380 … slot 7 = 0x000). Per slot, interleave 0x20:
//   [offs+0x00] flags : bit0 = enable, bit1 = flipy, bit2 = flipx
//   [offs+0x20] code  : 0..255  (index into the 16×16 sprite set in charram)
//   [offs+0x40] Y     : sy = 240 - Y
//   [offs+0x60] X     : sx = 240 - X
// Draw order slot 0→7 with later overwriting earlier ⇒ slot 7 (offs 0x000) is on top (MAME draws it last).
//
// GRAPHICS (gfx1 == charram $6000, same RAM as the FG chars — mirrored here via the charram write ports).
// spritelayout: 16×16, 3 planes, plane P at byte P*0x2000; per sprite 32 bytes/plane; the two 8-wide halves
// are byte-swapped. Pixel (col,row) of sprite `code`, plane P:
//   byte = code*32 + (col<8 ? 16 : 0) + row     ⇒ plane addr {code[7:0], (col<8), row[3:0]}  (13-bit)
//   bit  = 7 - (col & 7)                          (MSB-first, same as the FG FLIP-FIX)
//   pen3 = {p2_bit, p1_bit, p0_bit}               (transparent when pen3 == 0)
//   spr_pen = {1'b0, color_center_bot[1], pen3}   (color bank = (color_center_bot>>1)&1, parallels FG's bit0)
//
// NOTE (build-verify tunables): if sprites land 1px/1line off, nudge SPR_X_ADJ / SPR_Y_ADJ; if colors are off,
// the spr_pen palette mapping is the suspect (sprites can share or offset from the FG palette region).

`timescale 1 ps / 1 ps

module video_sprites (
    input  wire        clk_sys,
    input  wire        ce_pix,

    input  wire [8:0]  hcnt,
    input  wire [8:0]  vcnt,

    input  wire [7:0]  color_center_bot,

    // CPU write mirrors — descriptors (fgvideoram) and graphics (charram, 3 planes)
    input  wire        cpu_we_spr,
    input  wire [9:0]  cpu_spr_addr,
    input  wire [7:0]  cpu_spr_dout,
    input  wire        cpu_we_char_p0,
    input  wire        cpu_we_char_p1,
    input  wire        cpu_we_char_p2,
    input  wire [12:0] cpu_char_addr,
    input  wire [7:0]  cpu_char_dout,

    output reg  [4:0]  spr_pen,
    output reg         spr_priority
);

    localparam [7:0] SPR_X_ADJ = 8'd0;   // tune after first build if needed
    localparam [7:0] SPR_Y_ADJ = 8'd0;

    // ====================================================================
    // Descriptor mirror (a copy of fgvideoram; CPU writes mirrored in)
    // ====================================================================
    reg  [9:0] dsc_addr;
    wire [7:0] dsc_q;
    dpram #(.address_width(10), .data_width(8)) desc_mirror (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_spr),
        .address_a(cpu_spr_addr), .data_a(cpu_spr_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(1'b1), .wren_b(1'b0),
        .address_b(dsc_addr), .data_b(8'b0), .q_b(dsc_q)
    );

    // ====================================================================
    // Per-frame descriptor scan → 8 latched slots. Cycles a 32-step counter
    // (slot[2:0], byte[1:0]); one mirror read per ce_pix, 1-cycle BRAM delay.
    // ====================================================================
    reg        s_en  [0:7];
    reg        s_fx  [0:7];
    reg        s_fy  [0:7];
    reg  [7:0] s_code[0:7];
    reg  [7:0] s_sx  [0:7];   // 240 - X (8-bit; wrap handled by 8-bit position math below)
    reg  [7:0] s_sy  [0:7];   // 240 - Y

    reg  [4:0] scan, scan_d;
    wire [2:0] scan_spr  = scan[4:2];
    wire [1:0] scan_byte = scan[1:0];
    // addr = 0x380 - slot*0x80 + byte*0x20
    wire [9:0] scan_addr = 10'h380 - {scan_spr, 7'b0} + {scan_byte, 5'b0};

    always @(posedge clk_sys) begin
        if (ce_pix) begin
            // latch the byte requested last cycle (indexed by scan_d)
            case (scan_d[1:0])
                2'd0: begin
                    s_en[scan_d[4:2]] <= dsc_q[0];
                    s_fy[scan_d[4:2]] <= dsc_q[1];
                    s_fx[scan_d[4:2]] <= dsc_q[2];
                end
                2'd1: s_code[scan_d[4:2]] <= dsc_q;
                2'd2: s_sy[scan_d[4:2]]   <= 8'd240 - dsc_q + SPR_Y_ADJ;
                2'd3: s_sx[scan_d[4:2]]   <= 8'd240 - dsc_q + SPR_X_ADJ;
            endcase
            // request the next byte
            dsc_addr <= scan_addr;
            scan_d   <= scan;
            scan     <= scan + 1'b1;
        end
    end

    // ====================================================================
    // Per-pixel priority select: highest slot index covering (hcnt,vcnt) wins
    // (matches MAME draw order). 8-bit position math → +256 wrap is automatic.
    // ====================================================================
    integer k;
    reg        win_valid;
    reg  [7:0] win_code;
    reg        win_fx, win_fy;
    reg  [3:0] win_col;       // 0..15 within sprite
    reg  [3:0] win_row;
    reg  [7:0] dx, dy;
    always @(*) begin
        win_valid = 1'b0; win_code = 8'd0; win_fx = 1'b0; win_fy = 1'b0;
        win_col = 4'd0; win_row = 4'd0;
        for (k = 0; k < 8; k = k + 1) begin
            dx = hcnt[7:0] - s_sx[k];
            dy = vcnt[7:0] - s_sy[k];
            if (s_en[k] && (dx < 8'd16) && (dy < 8'd16)) begin
                win_valid = 1'b1;
                win_code  = s_code[k];
                win_fx    = s_fx[k];
                win_fy    = s_fy[k];
                win_col   = dx[3:0];
                win_row   = dy[3:0];
            end
        end
    end

    // per-sprite flip
    wire [3:0] gcol = win_fx ? (4'd15 - win_col) : win_col;
    wire [3:0] grow = win_fy ? (4'd15 - win_row) : win_row;

    // gfx plane address: {code, (col<8), row}  (col<8 ⇒ +16 half ⇒ ~gcol[3])
    wire [12:0] gfx_addr = {win_code, ~gcol[3], grow};

    // ====================================================================
    // Sprite graphics mirror (3 charram planes; CPU charram writes mirrored in)
    // ====================================================================
    wire [7:0] gp0, gp1, gp2;
    dpram #(.address_width(13), .data_width(8)) sgfx_p0 (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_char_p0),
        .address_a(cpu_char_addr), .data_a(cpu_char_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(ce_pix), .wren_b(1'b0),
        .address_b(gfx_addr), .data_b(8'b0), .q_b(gp0)
    );
    dpram #(.address_width(13), .data_width(8)) sgfx_p1 (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_char_p1),
        .address_a(cpu_char_addr), .data_a(cpu_char_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(ce_pix), .wren_b(1'b0),
        .address_b(gfx_addr), .data_b(8'b0), .q_b(gp1)
    );
    dpram #(.address_width(13), .data_width(8)) sgfx_p2 (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_char_p2),
        .address_a(cpu_char_addr), .data_a(cpu_char_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(ce_pix), .wren_b(1'b0),
        .address_b(gfx_addr), .data_b(8'b0), .q_b(gp2)
    );

    // ====================================================================
    // Output pipeline: register the bit-select + valid alongside the BRAM
    // address (1-cycle read latency), then decode the pen the next cycle.
    // ====================================================================
    reg  [2:0] bit_r;
    reg        valid_r;
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            bit_r   <= 3'd7 - gcol[2:0];   // MSB-first
            valid_r <= win_valid;
        end
    end

    wire [2:0] pen3 = { gp2[bit_r], gp1[bit_r], gp0[bit_r] };

    always @(posedge clk_sys) begin
        if (ce_pix) begin
            // SPRITE-OFF-TEST-2026-06-11 (RESOLVED): forcing this dark proved the top-right "numbers" ARE the
            // sprite layer (they vanished) — sprites render but mis-located/garbage. Test reverted; sprites ON.
            if (valid_r && (pen3 != 3'b000)) begin
                spr_pen      <= {1'b0, color_center_bot[1], pen3};
                spr_priority <= 1'b1;
            end else begin
                spr_pen      <= 5'b00000;
                spr_priority <= 1'b0;
            end
        end
    end

endmodule
