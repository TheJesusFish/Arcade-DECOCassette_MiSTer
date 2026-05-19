// DECO Cassette — Final pixel mixer + LS148 priority encoder (task 11)
// Implements the priority order from MAME screen_update_decocass (decocass_v.cpp:719-784)
// and draw_special_priority / draw_edge / draw_center effects.
//
// Priority order (from decocass_v.cpp 743-780):
//   1. Clear: fill with pen 8 (bg fill color)
//   2. If mode_set & 0x08: draw_edge ×2 (opaque, decocass_v.cpp:747-751)
//   3. If mode_set & 0x20: draw_center (opaque, decocass_v.cpp:753-755)
//      Else: draw_center, then draw_edge ×2 (transparent, decocass_v.cpp:757-764)
//   4. FG tilemap (transparent on pen 0, decocass_v.cpp:771)
//   5. Sprites (transparent on pen 0, decocass_v.cpp:774)
//   6. Missiles (transparent on pen 0, decocass_v.cpp:777)
//   7. draw_special_priority (headlight/tunnel pen-bit-4 modulation, decocass_v.cpp:780)
//
// Note: Edge and center layers are provided from upstream modules (video_bg in future).
// For now, we implement the priority mux only; edge/center detection is stubbed.

module deco_video_mixer (
    input  wire        clk_sys,
    input  wire        ce_pix,

    // Layer inputs (5-bit pens + opaque flags)
    input  wire [4:0]  fg_pen,   input  wire fg_opaque,
    input  wire [4:0]  bg_pen,   input  wire bg_opaque,
    input  wire [4:0]  spr_pen,  input  wire spr_opaque,
    input  wire [4:0]  mis_pen,  input  wire mis_opaque,

    // Control registers
    input  wire [7:0]  mode_set,            // E402: bits [3], [5], [6], [7] used
    input  wire [7:0]  color_center_bot,   // E408: color for center + bg tile flip
    input  wire [7:0]  color_missiles,     // E302: missile color select (unused here)

    // Edge/center geometry registers (for future draw_edge/draw_center detection)
    input  wire [7:0]  back_h_shift,       // E403 (edge horizontal scroll)
    input  wire [7:0]  back_vl_shift,      // E404 (edge left/top vertical scroll)
    input  wire [7:0]  back_vr_shift,      // E405 (edge right/bot vertical scroll)
    input  wire [7:0]  part_h_shift,       // E40A (headlight horiz center)
    input  wire [7:0]  part_v_shift,       // E40B (headlight vert center)
    input  wire [7:0]  center_h_shift_space,  // E40C
    input  wire [7:0]  center_v_shift,    // E40D

    // Pixel coordinate (for draw_edge/center/headlight logic in future phases)
    input  wire [8:0]  hcnt,
    input  wire [8:0]  vcnt,

    // Output to palette lookup
    output reg  [5:0]  out_pen,             // final 6-bit logical pen (0-63)
    output reg         out_pen_b4_modulate  // XOR pen[4] if headlight active
);

    // ========================================
    // Control register decoding
    // ========================================
    wire bkg_ena = mode_set[3];         // bit 3: edge enable
    wire cross_on = mode_set[5];        // bit 5: center opaque mode
    wire tunnel_active = mode_set[6];   // bit 6: tunnel flag
    wire part_h_enable = mode_set[7];   // bit 7: headlight enable

    // ========================================
    // Priority multiplexer following decocass_v.cpp 719-784
    // ========================================

    // Base fill color (pen 8, from decocass_v.cpp:744)
    localparam [5:0] BG_FILL = 6'd8;

    // BG layer is wired (video_bg rewrite 2026-05-17) but stays gated by
    // BIOS-controlled mode_set[3]. edge_valid still stubbed — proper
    // geometric edge-detection deferred until BG is verified visible.
    wire edge_valid = bg_opaque;
    wire center_valid = 1'b0;

    // TODO(verify-with-mame): draw_special_priority headlight/tunnel detection
    // decocass_v.cpp:235-290 checks:
    //   - crossing = mode_set[1:0] (0=outside, 1=exiting, 2=inside, 3=entering)
    //   - pri2 condition depends on crossing and back_h_shift (tunnel entry point)
    //   - objdata graphics match against headlight sprite bitmap
    //   - mode_set[7] = 1 to enable headlight sprite check
    //   - mode_set[5] = 0 to apply the effect (and priority[x,y] == 0)
    wire special_priority_active = 1'b0;
    wire headlight_pixel = 1'b0;        // set if pixel in headlight sprite
    wire headlight_b4_flip = 1'b0;      // XOR pen[4] when headlight active

    // ========================================
    // Priority resolution logic (combinatorial)
    // ========================================

    reg [5:0] pen_next;
    reg b4_modulate_next;

    always @(*) begin
        // Step 1: Start with bg fill (pen 8)
        pen_next = BG_FILL;
        b4_modulate_next = 1'b0;

        // Step 2: Draw edge opaque if bkg_ena and edge_valid
        // From decocass_v.cpp:747-751
        if (bkg_ena && edge_valid) begin
            pen_next = {1'b0, bg_pen};
            b4_modulate_next = 1'b0;
        end

        // Step 3: Draw center or edge transparent
        // From decocass_v.cpp:753-765
        if (center_valid) begin
            // Center color from decocass_v.cpp:292-304
            // Bits [4:2] of color_center_bot -> pen color [2:0]
            // But decocass_paletteram_w uses bits [2:0] of written byte as color index
            // For center: use color_center_bot bits as direct pen value
            // TODO(verify-with-mame): exact center pen index mapping
            pen_next = {2'b00, color_center_bot[2:0]};
            b4_modulate_next = 1'b0;
        end else if (!cross_on && bkg_ena && edge_valid) begin
            // Transparent edge mode (when NOT cross_on and bkg_ena)
            pen_next = {1'b0, bg_pen};
            b4_modulate_next = 1'b0;
        end

        // Step 4: FG tilemap (transparent on pen 0, decocass_v.cpp:771)
        if (fg_opaque && (fg_pen != 5'b00000)) begin
            pen_next = {1'b0, fg_pen};
            b4_modulate_next = 1'b0;
        end

        // Step 5: Sprites (transparent on pen 0, decocass_v.cpp:774)
        if (spr_opaque && (spr_pen != 5'b00000)) begin
            pen_next = {1'b0, spr_pen};
            b4_modulate_next = 1'b0;
        end

        // Step 6: Missiles (transparent on pen 0, decocass_v.cpp:777)
        if (mis_opaque && (mis_pen != 5'b00000)) begin
            pen_next = {1'b0, mis_pen};
            b4_modulate_next = 1'b0;
        end

        // Step 7: draw_special_priority (decocass_v.cpp:780)
        // TODO(verify-with-mame): full headlight/tunnel logic
        // From decocass_v.cpp:235-290:
        //   - crossing = mode_set[1:0]
        //   - if (crossing == 0 && !tunnel_active) return
        //   - if (!cross_on) return
        //   - color = bitswap + mask (decocass_v.cpp:243)
        //   - check objdata against pixel (y,x) in headlight sprite graphics
        //   - if match: pri2 = true; if pri2 and priority[y,x]==0: draw color
        //   - if (!pri2): set pen |= 0x10 (bit 4)
        if (special_priority_active && headlight_pixel) begin
            b4_modulate_next = headlight_b4_flip;
        end
    end

    // Registered output
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            out_pen <= pen_next;
            out_pen_b4_modulate <= b4_modulate_next;
        end
    end

endmodule
