// DECO Cassette — Background tilemap renderer (task 09)
//
// 2026-05-17 — FULL REWRITE. Previous version was completely stubbed
// (tile_code_byte and bitmap_byte hardcoded to 0). This version wires
// CPU writes through to internal BRAMs and produces real pixel output.
//
// MAME reference (decocass.cpp:961-970 tilelayout, decocass_v.cpp:130-163
// tile_offset, decocass_v.cpp:199-228 get_bg_*_tile_info):
//   - 32×32 tilemap of 16×16-pixel tiles
//   - 16 unique tile bitmaps (4-bit tile_code), 3 bits per pixel
//   - tilemap codes live in $D000-$D3FF (upper nibble of each byte)
//   - tile bitmaps share the same bytes: $D000-$D3FF holds plane 0
//     (in the upper nibble — bit positions 4..7), $D400-$D7FF holds
//     planes 1 and 2 interleaved (lower nibble = plane 1, upper = plane 2)
//   - get_bg_l/r_tile_info returns m_bgvideoram[tile_index] >> 4
//
// SIMPLIFICATIONS in this implementation:
//   - tile_offset LUT skipped — using direct {col, row} mapping. The
//     real MAME LUT (decocass_v.cpp:130-163) remaps the 32×32 grid to
//     non-linear memory layout. With direct mapping, the tilemap will
//     be SCRAMBLED but pixels will still flow. Good enough as a first
//     step to confirm BG is wired correctly; LUT can be added later.
//   - Single tilemap (no split between left/right halves with separate
//     scroll registers). Both halves render the same tilemap.
//
// Pixel-byte mapping (per MAME tilelayout):
//   tile N, row y, pixel x (16 pixels per row):
//     group   = x[3:2]                  (0..3 nibble groups)
//     bytaddr = N*64 + y + group*16     (4 distinct bytes per row per plane)
//     plane 0 byte at byaddr             (in $D000-$D3FF region)
//     plane 1+2 byte at byaddr + 1024   (in $D400-$D7FF region)
//     plane 0 pixel bit = byte[4 + x[1:0]]  (upper nibble)
//     plane 1 pixel bit = byte[0 + x[1:0]]  (lower nibble of $D4xx byte)
//     plane 2 pixel bit = byte[4 + x[1:0]]  (upper nibble of $D4xx byte)

module video_bg (
    input  wire        clk_sys,
    input  wire        ce_pix,

    input  wire [8:0]  hcnt,
    input  wire [8:0]  vcnt,

    // Scroll/mode registers (currently unused — scroll deferred)
    input  wire [7:0]  back_h_shift,
    input  wire [7:0]  back_vl_shift,
    input  wire [7:0]  back_vr_shift,
    input  wire [7:0]  mode_set,

    // FG color register — also drives BG color (decocass_v.cpp:201-204)
    input  wire [7:0]  color_center_bot,

    // CPU write port (shared $D000-$D7FF, 11-bit address)
    input  wire        cpu_we_tile,
    input  wire [10:0] cpu_addr_tile,
    input  wire [7:0]  cpu_dout,

    // Render outputs
    output reg  [4:0]  bg_pen,
    output reg         bg_opaque
);

    // ========================================
    // Internal timing / coordinate derivation
    // No scroll applied yet — TODO: add scroll later
    // ========================================
    wire [4:0] tile_col = {1'b0, hcnt[7:4]};   // 0..15 visible (tilemap is 32 wide)
    wire [4:0] tile_row = {1'b0, vcnt[7:4]};
    wire [3:0] pix_x    = hcnt[3:0];           // 0..15 pixel within tile
    wire [3:0] pix_y    = vcnt[3:0];

    // ========================================
    // tile_offset LUT — derived from decocass_v.cpp:130-163.
    // Table is structured as 4 column-quadrants × 2 row-halves:
    //   col[4:3]==00 (cols 0..7):   base = 0x078 + col[2:0]    (increment by 1)
    //   col[4:3]==01 (cols 8..15):  base = 0x0ff - col[2:0]    (decrement by 1)
    //   col[4:3]==10 (cols 16..23): base = 0x278 + col[2:0]
    //   col[4:3]==11 (cols 24..31): base = 0x2ff - col[2:0]
    //   row[4]==0    (rows 0..15):  row_offset = 0
    //   row[4]==1    (rows 16..31): row_offset = 0x100
    //   tile_index = base + row_offset - row[3:0]*8
    // ========================================
    // TILE-OFFSET-FIX-2026-06-10: the prior LUT had col/row TRANSPOSED (added col, subtracted row*8) → every BG
    // tile scrambled. MAME mapper is tile_offset[col*32+row] (decocass_v.cpp:130-163). Verified directly against
    // the table: base = 0x078 - col*8; rows 0..7 ADD row; rows 8..15 MIRROR as (base + 0x08f - row).
    //   col0row0=0x078 col0row1=0x079 col1row0=0x070 col15row0=0x000 col0row8=0x0ff col0row15=0x0f8 ✓
    // (16-col × 16-row visible area, no scroll yet. Remaining BG TODOs: per-tile bitmap group order may still be
    //  reversed; the get_bg_l/r split's `tile_index & 0x80` empty-tile masking is not implemented.)
    wire [9:0] bg_base    = 10'h078 - {3'b0, tile_col[3:0], 3'b0};   // 0x078 - col*8  (col 0..15 → 0x078..0x000)
    wire [9:0] tile_index = tile_row[3] ? (bg_base + 10'h08f - {6'b0, tile_row[3:0]})   // rows 8..15 (mirrored)
                                        : (bg_base + {6'b0, tile_row[3:0]});            // rows 0..7

    // ========================================
    // BRAM #1: tile codes (also doubles as plane-0 bitmap source).
    // $D000-$D3FF = first 1KB of tileram. CPU writes when cpu_addr_tile < 0x400.
    // ========================================
    wire cpu_we_tile_lo = cpu_we_tile && (cpu_addr_tile < 11'h400);
    wire cpu_we_tile_hi = cpu_we_tile && (cpu_addr_tile >= 11'h400);

    wire [7:0] tilecode_byte;
    dpram #(.address_width(10), .data_width(8)) bg_tilecodes_inst (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_tile_lo),
        .address_a(cpu_addr_tile[9:0]), .data_a(cpu_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(ce_pix), .wren_b(1'b0),
        .address_b(tile_index), .data_b(8'b0), .q_b(tilecode_byte)
    );

    // Latch tile_code and pixel coordinates 1 cycle (waiting for tilecode_byte)
    // BG-FLIPY-FIX-2026-06-10: MAME draws the bit7-set cells via get_bg_r_tile_info with TILE_FLIPY
    // (decocass_v.cpp:210-217). For our single static tilemap (no per-half scroll) that's just: flip Y on
    // tile_index[7] cells. (The literal &0x80 EMPTY mask is only for the two-tilemap split + separate scroll,
    // which we don't have — masking here would blank half the screen, so we flip instead.)
    wire [3:0] eff_pix_y = tile_index[7] ? (4'd15 - pix_y) : pix_y;
    reg [3:0] s1_tile_code;
    reg [3:0] s1_pix_x, s1_pix_y;
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            s1_tile_code <= tilecode_byte[7:4];
            s1_pix_x     <= pix_x;
            s1_pix_y     <= eff_pix_y;
        end
    end

    // ========================================
    // BRAM #2: plane 0 bitmap (same memory as tile codes — $D000-$D3FF).
    //   byte_addr = tile_code*64 + pix_y + pix_x[3:2]*16
    // We use a separate dpram so we can read tile codes and plane 0 simultaneously.
    // CPU writes are mirrored from the same $D000-$D3FF range.
    // ========================================
    // BG-BITMAP-FIX-2026-06-10: group order reversed per tilelayout xoffset = (3 - x[3:2])*16 (was x[3:2]*16).
    wire [9:0] plane0_addr = {s1_tile_code[3:0], 6'b0} + {6'b0, s1_pix_y[3:0]} + {4'b0, (2'd3 - s1_pix_x[3:2]), 4'b0};
    wire [7:0] plane0_byte;
    dpram #(.address_width(10), .data_width(8)) bg_plane0_inst (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_tile_lo),
        .address_a(cpu_addr_tile[9:0]), .data_a(cpu_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(ce_pix), .wren_b(1'b0),
        .address_b(plane0_addr), .data_b(8'b0), .q_b(plane0_byte)
    );

    // ========================================
    // BRAM #3: planes 1+2 bitmap ($D400-$D7FF).
    //   byte_addr = tile_code*64 + pix_y + pix_x[3:2]*16   (in second 1KB)
    // CPU writes from cpu_addr_tile[9:0] when cpu_addr_tile[10] is set.
    // ========================================
    wire [9:0] plane12_addr = plane0_addr;  // same offset within the second 1KB region
    wire [7:0] plane12_byte;
    dpram #(.address_width(10), .data_width(8)) bg_plane12_inst (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_tile_hi),
        .address_a(cpu_addr_tile[9:0]), .data_a(cpu_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(ce_pix), .wren_b(1'b0),
        .address_b(plane12_addr), .data_b(8'b0), .q_b(plane12_byte)
    );

    // ========================================
    // Latch second stage (pix_x[1:0] needs to align with byte data)
    // ========================================
    reg [1:0] s2_pix_x_lo;
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            s2_pix_x_lo <= s1_pix_x[1:0];
        end
    end

    // Extract pixel bits from the bytes:
    //   plane 0: byte[4 + pix_x[1:0]] — upper nibble of $D0xx byte
    //   plane 1: byte[0 + pix_x[1:0]] — lower nibble of $D4xx byte
    //   plane 2: byte[4 + pix_x[1:0]] — upper nibble of $D4xx byte
    // BG-BITMAP-FIX-2026-06-10: MSB-first (like the FG FLIP-FIX) + correct nibbles per tilelayout planeoffset
    // {8196,8192,4} (decocass.cpp:961): pen LSB(p0) = $D000 LOWER nibble bit(3-x); p1 = $D400 UPPER nibble bit(7-x);
    // pen MSB(p2) = $D400 LOWER nibble bit(3-x). (Was nibbles swapped + LSB-first.)
    wire [2:0] bg_xlo = {1'b0, s2_pix_x_lo};        // 0..3
    wire p0 = plane0_byte [3'd3 - bg_xlo];          // $D000 lower nibble, MSB-first
    wire p1 = plane12_byte[3'd7 - bg_xlo];          // $D400 upper nibble, MSB-first
    wire p2 = plane12_byte[3'd3 - bg_xlo];          // $D400 lower nibble, MSB-first

    wire [2:0] pen = {p2, p1, p0};

    // ========================================
    // Output: palette index per MAME get_bg_l_tile_info (decocass_v.cpp:199-208):
    //   color = (m_color_center_bot >> 7) & 1  (1 bit)
    //   tileinfo.set(2, tile_code, color * 4 + 1, 0)
    // gfx 2 has 8 color sets × 8 pens (3bpp). Effective palette index:
    //   {color*4+1, pen[2:0]}  — 6 bits, but bg_pen is 5 bits.
    //   For our purposes: {color, pen[2:0]} gives 16 entries (palette[0..15]).
    // Use {1'b0, color, pen[2:0]} (5-bit). Transparent on pen=0.
    // ========================================
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            bg_pen    <= {1'b0, color_center_bot[7], pen};
            bg_opaque <= (pen != 3'b000);
        end
    end

endmodule
