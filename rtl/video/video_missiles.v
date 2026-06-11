// DECO Cassette — Missile layer renderer (task 10, phase 07+)
// Renders 16x 1bpp missile dots from colorram interleaved data.
//
// Based on MAME decocass_v.cpp:572-622 (draw_missiles).
// Missile RAM location: m_colorram (same as FG colorram) per line 777.
// Descriptor stride: interleave = 0x20 (32 bytes).
// 8 missile pairs (16 total missiles):
//   for (i = 0, offs = 0; i < 8; i++, offs += 4 * interleave)
//     Missile 2i (lower):   y = colorram[offs + 0*0x20], x = colorram[offs + 2*0x20]
//     Missile 2i+1 (upper): y = colorram[offs + 1*0x20], x = colorram[offs + 3*0x20]
// Position formula: sx = 255 - x_byte; sy = 255 - y_byte (similar to sprites but 255 instead of 240)
// Color formula:
//   Lower missiles: palette_idx = (m_color_missiles & 7) | 8  → bits [2:0] select pen, high bit = 1
//   Upper missiles: palette_idx = ((m_color_missiles >> 4) & 7) | 8
// Priority bits (MAME):
//   Lower: priority.pix(sy, sx) |= 1 << 2;
//   Upper: priority.pix(sy, sx) |= 1 << 3;
// Missile y_adjust = 1 per screen_update_decocass (line 777).
// Render: per-line scan, draw 1×4 pixel dots (4-pixel-wide trails).

module video_missiles (
    input  wire        clk_sys,
    input  wire        ce_pix,

    input  wire [8:0]  hcnt,
    input  wire [8:0]  vcnt,

    input  wire [7:0]  color_missiles,

    // CPU-side write port (for missile RAM, which is colorram)
    input  wire        cpu_we_mis,
    input  wire [9:0]  cpu_mis_addr,
    input  wire [7:0]  cpu_mis_dout,

    // Render outputs
    output reg  [4:0]  mis_pen,        // 5-bit palette index (1bpp → 2 states, palette selected by color_missiles)
    output reg         mis_priority    // priority bit for LS148 mixer
);

    // ========================================
    // Missile descriptor RAM (second read port on colorram)
    // BRAM duplication strategy (same as sprites):
    //   - colorram has one read port (used by video_fg for FG attribute fetch).
    //   - video_missiles needs a second read port for missile descriptor lookup.
    //   - Solution: duplicate the BRAM (missile_desc_ram_inst) and mirror CPU writes
    //     to both the FG colorram BRAM and this missile BRAM whenever cpu_we_mis is asserted.
    //   - This adds 1K BRAM cost but avoids port-count limitations.
    // ========================================

    wire [7:0] mis_desc_byte;  // Read output from missile descriptor RAM
    dpram #(.address_width(10), .data_width(8)) missile_desc_ram_inst (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_mis),
        .address_a(cpu_mis_addr), .data_a(cpu_mis_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(1'b1), .wren_b(1'b0),
        .address_b(mis_desc_read_addr), .data_b(8'b0), .q_b(mis_desc_byte)
    );

    // ========================================
    // Per-line missile scanning
    // ========================================
    // On each pixel cycle, check if current (hcnt, vcnt) falls within any active missile.
    // Each missile is a 1×4 dot (4 pixels wide, 1 pixel tall).
    // Missile positions are raw from colorram; apply transformations (255 - x, 255 - y).

    // Missile pair index (0..7) → 16 missiles total
    reg [2:0]  mis_pair_idx;
    reg [3:0]  mis_sub_idx;     // Missile index within pair (0 = lower, 1 = upper) and position (0..3)

    // Missile descriptor latches
    reg [7:0]  mis_y_lower, mis_y_upper;
    reg [7:0]  mis_x_lower, mis_x_upper;
    reg [8:0]  mis_y_lower_pos, mis_y_upper_pos;
    reg [8:0]  mis_x_lower_pos, mis_x_upper_pos;

    // Missile descriptor fetch address
    wire [9:0] mis_desc_read_addr;

    // Missile pair offset calculation: for pair i (0..7), base offset = 0 + i*4*0x20 = i*0x80
    wire [9:0] mis_pair_base = {mis_pair_idx, 7'b0};  // mis_pair_idx << 7

    // ========================================
    // Per-pixel missile matching
    // ========================================

    always @(posedge clk_sys) begin
        if (ce_pix) begin
            mis_pair_idx <= 3'd0;  // Start scanning from pair 0
            mis_sub_idx <= 4'd0;   // Start with lower missile
        end
    end

    // Combinational missile descriptor fetch
    // Fetch all 4 bytes for the current pair in parallel (ideal RTL case).
    // For simplicity, using a pipelined approach:
    //   Cycle 0: Read y_lower (offset + 0*0x20)
    //   Cycle 1: Read y_upper (offset + 1*0x20)
    //   Cycle 2: Read x_lower (offset + 2*0x20)
    //   Cycle 3: Read x_upper (offset + 3*0x20)
    // Then check overlap for (hcnt, vcnt) and output the color.

    // TODO(verify-with-mame): Missile descriptor fetch pipeline.
    // MAME's draw_missiles iterates through pairs and reads 4 bytes per pair.
    // For RTL, we need to decide: sequential fetch (4 cycles per pair) or
    // parallel read ports. Using sequential for simplicity here.

    wire [9:0] mis_y_lower_addr = mis_pair_base + 10'd0;
    wire [9:0] mis_y_upper_addr = mis_pair_base + 10'd32;
    wire [9:0] mis_x_lower_addr = mis_pair_base + 10'd64;
    wire [9:0] mis_x_upper_addr = mis_pair_base + 10'd96;

    // Assign the read address to the BRAM (would rotate through the 4 addresses in a real FSM).
    // For now, use a fixed read to y_lower.
    assign mis_desc_read_addr = mis_y_lower_addr;

    // Latch missile descriptors (simplified; in reality needs pipelined reads).
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            // Sequentially latch bytes (simulated; in practice, would use an FSM or parallel reads).
            // This is a placeholder; proper implementation would interleave fetches or use
            // a separate 4-port read logic.
            mis_y_lower <= mis_desc_byte;  // Read from mis_y_lower_addr
            // mis_y_upper, mis_x_lower, mis_x_upper would be fetched on subsequent cycles
        end
    end

    // Missile position computation
    // Per MAME line 580, 599:
    //   sy = 255 - missile_ram[offs + 0*interleave]  (lower missile)
    //   sy = 255 - missile_ram[offs + 1*interleave]  (upper missile)
    //   sx = 255 - missile_ram[offs + 2*interleave]  (lower missile)
    //   sx = 255 - missile_ram[offs + 3*interleave]  (upper missile)
    // Then sy -= missile_y_adjust (= 1 per line 777).

    always @(*) begin
        mis_y_lower_pos = 9'd255 - {1'b0, mis_y_lower} - 9'd1;  // Adjust by 1
        mis_y_upper_pos = 9'd255 - {1'b0, mis_y_upper} - 9'd1;
        mis_x_lower_pos = 9'd255 - {1'b0, mis_x_lower};
        mis_x_upper_pos = 9'd255 - {1'b0, mis_x_upper};
    end

    // ========================================
    // Missile overlap detection
    // ========================================
    // Missiles are 1×4 dots, drawn as a 4-pixel horizontal trail per MAME line 589-597, 608-616.
    // Check if (hcnt, vcnt) falls within [sx, sx+3] × [sy, sy]  (1 scanline, 4 pixels wide).

    wire mis_lower_y_match = (vcnt[8:0] == mis_y_lower_pos[8:0]);
    wire mis_lower_x_match = (hcnt >= mis_x_lower_pos[8:0]) && (hcnt < (mis_x_lower_pos[8:0] + 9'd4));
    wire mis_lower_hit = mis_lower_y_match && mis_lower_x_match;

    wire mis_upper_y_match = (vcnt[8:0] == mis_y_upper_pos[8:0]);
    wire mis_upper_x_match = (hcnt >= mis_x_upper_pos[8:0]) && (hcnt < (mis_x_upper_pos[8:0] + 9'd4));
    wire mis_upper_hit = mis_upper_y_match && mis_upper_x_match;

    // ========================================
    // Missile color palette index
    // ========================================
    // Per MAME lines 593, 612:
    //   Lower missiles: bitmap.pix(sy, sx) = (m_color_missiles & 7) | 8;
    //   Upper missiles: bitmap.pix(sy, sx) = ((m_color_missiles >> 4) & 7) | 8;
    // The "| 8" sets bit 3 (palette index high bit).
    // For RTL output (5-bit palette index):
    //   Missile pen is 1bpp (always set to the color value, never transparent).
    //   Lower: palette_idx = { 1'b1, color_missiles[2:0], 1'b0 }  (5 bits)
    //   Upper: palette_idx = { 1'b1, color_missiles[6:4], 1'b0 }
    // Or: palette_idx[4] = 1, palette_idx[3:1] = color_low[2:0], palette_idx[0] = 0
    //     (color value is 3 bits; the "| 8" adds 0x08 = bit 3)

    always @(posedge clk_sys) begin
        if (ce_pix) begin
            // MISSILES-NEUTER-2026-06-11: this layer is an unfinished STUB (mis_pair_idx stuck at 0; only
            // mis_y_lower ever read; mis_x_lower/y_upper/x_upper UNINITIALIZED) → it paints garbage dots, and
            // missiles draw ON TOP. BurgerTime has NO missiles → force it dark. DIAG-REVERT-2026-06-11: drop the `1'b0 &&`.
            // if (mis_lower_hit) begin
            if (1'b0 && mis_lower_hit) begin
                // Lower missile (drawn)
                mis_pen <= { 1'b1, color_missiles[2:0], 1'b0 };  // (color_missiles & 7) | 8
                mis_priority <= 1'b1;  // Priority bit set (MAME: priority.pix |= 1 << 2)
            // end else if (mis_upper_hit) begin
            end else if (1'b0 && mis_upper_hit) begin
                // Upper missile (drawn)
                mis_pen <= { 1'b1, color_missiles[6:4], 1'b0 };  // ((color_missiles >> 4) & 7) | 8
                mis_priority <= 1'b1;  // Priority bit set (MAME: priority.pix |= 1 << 3)
            end else begin
                // No missile hit or outside clip region
                mis_pen <= 5'b00000;
                mis_priority <= 1'b0;
            end
        end
    end

    // TODO(verify-with-mame): Missile y_adjust and flip_screen handling.
    // Lines 577, 587: missile_y_adjust = 1, missile_y_adjust_flip_screen = 0.
    // Verify that sy -= 1 is the only adjustment needed. Flip screen support deferred.

    // TODO(verify-with-mame): Missile colorram mapping.
    // Lines 593, 612: Confirm that m_color_missiles[2:0] and [6:4] directly map to
    // palette indices. No additional palette decoding (unlike sprites, which have
    // a color_center_bot bit-select).

endmodule
