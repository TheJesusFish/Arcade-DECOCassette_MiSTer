// DECO Cassette — Sprite layer renderer (task 10, phase 07+)
// Fetches and renders 8x 16×16 2bpp sprites from fgvideoram descriptors.
//
// Based on MAME decocass_v.cpp:524-569 (draw_sprites).
// Sprite RAM location confirmed: m_fgvideoram (same as FG tilemap) per line 774.
// Descriptor stride: interleave = 0x20 (32 bytes).
// Sprite layout (8 sprites):
//   Offset = 28*0x20 - i*4*0x20 (i=0..7), so backwards iteration
//   Each sprite occupies 4 interleaved 16-bit words:
//     [offs + 0*0x20]: flags byte (bit 0 = enable, bits [2:1] = flipx/flipy)
//     [offs + 1*0x20]: sprite code (character index into gfxdecode)
//     [offs + 2*0x20]: Y position (240 - pos)
//     [offs + 3*0x20]: X position (240 - pos)
// Color bank: ((color_center_bot >> 1) & 1) selects one of 2 palette banks (2 bits of pen selection).
// Sprite y_adjust = 0 per screen_update_decocass (line 774).
// Render: per-line scan across all sprite slots, draw 16×16 at (sx, sy).

module video_sprites (
    input  wire        clk_sys,
    input  wire        ce_pix,

    input  wire [8:0]  hcnt,
    input  wire [8:0]  vcnt,

    input  wire [7:0]  color_center_bot,

    // CPU-side write port (for sprite descriptor RAM, which is fgvideoram)
    input  wire        cpu_we_spr,
    input  wire [9:0]  cpu_spr_addr,
    input  wire [7:0]  cpu_spr_dout,

    // Render outputs
    output reg  [4:0]  spr_pen,        // 5-bit palette index
    output reg         spr_priority    // priority bit for LS148 mixer
);

    // ========================================
    // Sprite descriptor RAM (second read port on fgvideoram)
    // BRAM duplication strategy:
    //   - fgvideoram has one read port (used by video_fg for tile fetch).
    //   - video_sprites needs a second read port for sprite descriptor lookup.
    //   - Solution: duplicate the BRAM (sprite_desc_ram_inst) and mirror CPU writes
    //     to both the tilemap BRAM and this sprite BRAM whenever cpu_we_spr is asserted.
    //   - This adds 1K BRAM cost but avoids port-count limitations on M9K blocks.
    //   - Both BRAMs are written identically; the tilemap reader and sprite reader
    //     work independently without contention.
    // ========================================

    wire [7:0] spr_desc_byte;  // Read output from sprite descriptor RAM
    dpram #(.address_width(10), .data_width(8)) sprite_desc_ram_inst (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(cpu_we_spr),
        .address_a(cpu_spr_addr), .data_a(cpu_spr_dout), .q_a(),
        .clock_b(clk_sys), .enable_b(1'b1), .wren_b(1'b0),
        .address_b(spr_desc_read_addr), .data_b(8'b0), .q_b(spr_desc_byte)
    );

    // ========================================
    // Per-line sprite scanning and rendering
    // ========================================
    // On each scanline, iterate through all 8 sprite slots and check if any
    // sprite overlaps the current pixel. If so, latch its color and priority.
    // Sprites are 16×16, so we need to check:
    //   - Is the sprite enabled (bit 0 of flags byte)?
    //   - Does the sprite Y range [sy, sy+16) contain vcnt?
    //   - Does the sprite X range [sx, sx+16) contain hcnt?
    // If all conditions are met, fetch the sprite code, apply flipx/flipy,
    // compute the pixel color, and output it.

    // Sprite slot index (0..7)
    reg [2:0]  spr_slot;
    reg [3:0]  spr_sub_x;     // Sub-pixel X position within sprite (0..15)
    reg [3:0]  spr_sub_y;     // Sub-pixel Y position within sprite (0..15)

    // Current sprite descriptor latch
    reg [7:0]  spr_flags;     // flags byte (bit 0 = enable, [2:1] = flipx/flipy)
    reg [7:0]  spr_code;      // sprite code (character index)
    reg [7:0]  spr_y_raw;     // raw Y position from RAM
    reg [7:0]  spr_x_raw;     // raw X position from RAM
    reg [8:0]  spr_y_pos;     // computed Y position (240 - spr_y_raw)
    reg [8:0]  spr_x_pos;     // computed X position (240 - spr_x_raw)

    // Sprite gfxram read address (for 16×16 sprite pixel lookup)
    reg [10:0] spr_gfx_addr;  // {code[5:0], sub_y[3:0], sub_x[1:0]}
    wire [7:0] spr_gfx_lo, spr_gfx_hi;

    // Sprite gfxram (two planes, 2bpp per pixel)
    dpram #(.address_width(11), .data_width(8)) spr_gfx_lo_inst (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(1'b0),
        .address_a(10'b0), .data_a(8'b0), .q_a(),
        .clock_b(clk_sys), .enable_b(ce_pix), .wren_b(1'b0),
        .address_b(spr_gfx_addr), .data_b(8'b0), .q_b(spr_gfx_lo)
    );

    dpram #(.address_width(11), .data_width(8)) spr_gfx_hi_inst (
        .clock_a(clk_sys), .enable_a(1'b1), .wren_a(1'b0),
        .address_a(10'b0), .data_a(8'b0), .q_a(),
        .clock_b(clk_sys), .enable_b(ce_pix), .wren_b(1'b0),
        .address_b(spr_gfx_addr), .data_b(8'b0), .q_b(spr_gfx_hi)
    );

    // TODO(verify-with-mame): Sprite gfxram should be loaded from ROM or initialized.
    // For now, leaving as TODO. MAME gfxdecode->gfx(1) decodes sprite graphics.

    // ========================================
    // Sprite descriptor fetch state machine
    // ========================================
    // Each sprite occupies 4 interleaved locations (stride = 0x20 = 32 bytes).
    // Sprite 0: offs = 28*32 = 224 (0xE0)
    // Sprite 1: offs = 224 - 128 = 96  (0x60)
    // ...
    // Sprite 7: offs = 224 - 896 = -672 (wraps in 1K: 0x200 + ... )

    // Sprite slot offset calculation: for slot i (0..7), base offset = 28*0x20 - i*4*0x20
    // This simplifies to: base_offset = 224 - 128*i (with wrap-around in 10 bits)
    // Read the four descriptor bytes for the current sprite slot from sprite_desc_ram.

    wire [9:0] spr_slot_base = 10'd224 - ({spr_slot, 4'd0} << 3) + ({spr_slot, 7'd0});
    // Cleaner: spr_slot_base = 224 - 128*spr_slot = 224 - (spr_slot << 7)
    wire [9:0] spr_slot_base_calc = 10'd224 - ({spr_slot, 7'b0});

    wire [9:0] spr_desc_read_addr;  // Read address for sprite descriptor

    // TODO(verify-with-mame): MAME iterates sprites backwards (i from 7 to 0).
    // Line 530: for (int i = 0; i < 8; i++, offs -= 4 * interleave)
    // This is a per-frame iteration in the blitter, not per-pixel. For RTL, we
    // iterate per scanline to check overlaps. Confirm sprite rendering order.

    // Per-pixel matching: For each visible pixel (hcnt, vcnt) in range [0..255, 8..247],
    // iterate through all 8 sprite slots and check if (hcnt, vcnt) falls within any sprite.
    // If a hit, fetch the sprite descriptor, compute the sub-pixel address, and look up
    // the 2bpp pixel color. Output the highest-priority match (or black if no match).

    // For simplicity, use a combinational per-line scan: on each scanline (ce_pix && hcnt < 256),
    // loop through 8 slots and find the first matching sprite. This is a "sprite priority"
    // scheme where lower slot numbers have higher priority (Sprite 0 > Sprite 1, etc.).

    always @(posedge clk_sys) begin
        if (ce_pix) begin
            // Each pixel cycle, check if current (hcnt, vcnt) hits any active sprite.
            // Start iteration from slot 0 (will loop in FSM or combinational logic).
            spr_slot <= 3'd0;
            spr_sub_x <= hcnt[3:0];  // Sub-pixel X within sprite
            spr_sub_y <= vcnt[3:0];  // Sub-pixel Y within sprite
        end
    end

    // Combinational sprite descriptor fetch
    // Given spr_slot, compute the read address and latch the bytes.
    wire [9:0] spr_byte0_addr = spr_slot_base_calc + 10'd0;
    wire [9:0] spr_byte1_addr = spr_slot_base_calc + 10'd32;
    wire [9:0] spr_byte2_addr = spr_slot_base_calc + 10'd64;
    wire [9:0] spr_byte3_addr = spr_slot_base_calc + 10'd96;

    assign spr_desc_read_addr = spr_byte0_addr;  // Fetch byte 0 (flags)

    // TODO(verify-with-mame): Need to implement a 4-cycle pipelined fetch to get all 4 bytes.
    // For now, using a simplified state machine placeholder.

    always @(posedge clk_sys) begin
        if (ce_pix) begin
            // Latch sprite descriptor bytes (MAME lines 534-538)
            spr_flags <= spr_desc_byte;  // offs + 0
            // spr_code, spr_y_raw, spr_x_raw fetched in subsequent cycles
        end
    end

    // ========================================
    // Sprite position computation
    // ========================================
    // Per MAME:
    //   sx = 240 - sprite_ram[offs + 3 * interleave]
    //   sy = 240 - sprite_ram[offs + 2 * interleave]
    // Note: This is relative to the 256×240 visible area.

    always @(*) begin
        spr_x_pos = 9'd240 - {1'b0, spr_x_raw};
        spr_y_pos = 9'd240 - {1'b0, spr_y_raw};
    end

    // ========================================
    // Sprite overlap detection and rendering
    // ========================================
    // Check if (hcnt, vcnt) falls within [sx, sx+16) × [sy, sy+16).

    wire spr_enabled = spr_flags[0];
    wire spr_flipx = spr_flags[2];
    wire spr_flipy = spr_flags[1];

    wire spr_x_match = (hcnt >= spr_x_pos[8:0]) && (hcnt < (spr_x_pos[8:0] + 9'd16));
    wire spr_y_match = (vcnt >= spr_y_pos[8:0]) && (vcnt < (spr_y_pos[8:0] + 9'd16));
    wire spr_hit = spr_enabled && spr_x_match && spr_y_match;

    // TODO(verify-with-mame): Sprite sub-pixel address calculation.
    // MAME uses gfxdecode->gfx(1)->prio_transpen(...) which applies
    // flipx/flipy transformations and draws the sprite. For RTL, we need to:
    //   1. Compute the sub-pixel position within the 16×16 sprite.
    //   2. Apply flipx/flipy to mirror the address if needed.
    //   3. Look up the 2bpp pixel from spr_gfx_ram.
    //   4. Apply the color bank to select palette index.

    reg [3:0] spr_fx, spr_fy;  // Flipped coordinates
    always @(*) begin
        spr_fx = spr_flipx ? (4'd15 - spr_sub_x) : spr_sub_x;
        spr_fy = spr_flipy ? (4'd15 - spr_sub_y) : spr_sub_y;
    end

    // Sprite gfxram address: {code[5:0], fy[3:0], fx[1:0]}
    // (Assuming 8×8 tiles packed into the gfxram, 4 tiles per sprite row)
    always @(*) begin
        spr_gfx_addr = {spr_code[5:0], spr_fy, spr_fx[1:0]};
    end

    // Sprite color palette index (5 bits)
    // pen = { spr_gfx_hi[spr_fx[2:0]], spr_gfx_lo[spr_fx[2:0]] }  (2 bits)
    // color_bank = (color_center_bot >> 1) & 1  (1 bit)
    // palette_idx = { color_bank, attr[1:0], pen[1:0] }  (5 bits)
    // TODO(verify-with-mame): Sprite palette index calculation. MAME uses color as a parameter
    // to gfxdecode->gfx(1)->prio_transpen(), which selects the palette bank.
    // Assuming: palette_idx = { color_center_bot[1], 2'b00, pen[1:0] }

    reg [1:0] spr_pen_2bpp;
    always @(*) begin
        // Extract 2bpp pixel from sprite graphics data
        // spr_fx[2] selects which nibble (high or low) of the byte
        spr_pen_2bpp = spr_fx[2] ? {spr_gfx_hi[7-spr_fx[1:0]], spr_gfx_lo[7-spr_fx[1:0]]} :
                                   {spr_gfx_hi[3-spr_fx[1:0]], spr_gfx_lo[3-spr_fx[1:0]]};
    end

    wire [1:0] color_bank = {(color_center_bot >> 1) & 1'b1, 1'b0};  // Expands to 2 bits
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            if (spr_hit && (spr_pen_2bpp != 2'b00)) begin
                // Non-transparent sprite pixel
                spr_pen <= {color_bank[0], 2'b00, spr_pen_2bpp};
                spr_priority <= 1'b1;  // Sprite has priority
            end else begin
                // No sprite hit or transparent pixel
                spr_pen <= 5'b00000;
                spr_priority <= 1'b0;
            end
        end
    end

endmodule
