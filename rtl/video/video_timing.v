// DECO Cassette — Video timing generator (task 07)
// Raster counters + HSYNC/VSYNC/HBLANK/VBLANK generation
// Derived from MAME's set_raw(HCLK, 384, 0*8, 256, 272, 1*8, 248)
//
// Pixel clock:  6.000 MHz (ce_pix = ce_hclk from clock_div)
// Horizontal:   384 total, visible 0..255 (256 pixels)
// Vertical:     272 total, visible 8..247 (240 lines)
// Refresh:      ~57.42 Hz

module video_timing (
    input  wire        clk_sys,
    input  wire        ce_pix,    // 6 MHz clock enable (1 per pixel)
    input  wire        reset,

    output reg  [8:0]  hcnt,      // 0..383 (horizontal counter)
    output reg  [8:0]  vcnt,      // 0..271 (vertical counter)

    output reg         hblank,    // 1 outside visible window (h > 255)
    output reg         vblank,    // 1 outside visible window (v < 8 or v > 247)

    output reg         hsync,     // HSYNC pulse in hblank region
    output reg         vsync,     // VSYNC pulse in vblank region

    output reg         vsync_pulse // single-cycle strobe on VSYNC rising edge
);

    // Horizontal counter wraps at 384
    always @(posedge clk_sys) begin
        if (reset) begin
            hcnt <= 9'd0;
        end else if (ce_pix) begin
            if (hcnt == 9'd383) begin
                hcnt <= 9'd0;
            end else begin
                hcnt <= hcnt + 9'd1;
            end
        end
    end

    // Vertical counter wraps at 272, increments at end of horizontal line
    always @(posedge clk_sys) begin
        if (reset) begin
            vcnt <= 9'd0;
        end else if (ce_pix && hcnt == 9'd383) begin
            if (vcnt == 9'd271) begin
                vcnt <= 9'd0;
            end else begin
                vcnt <= vcnt + 9'd1;
            end
        end
    end

    // HBLANK: high when hcnt > 255 (outside visible 0..255)
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            // VIDEO-TRIM-2026-06-28: blank the last 8 active px (hcnt 248..255) = the display-BOTTOM 8 rows
            // (ROT270: hcnt+ = display-down). The VID_HV_DELAY phase-fix aligned the top; this trims the residual
            // wrap-garbage band the phase shift pushed to the bottom. Was `hcnt > 9'd255` (full 256-wide active).
            // VIDEO-WINDOW-CROP-2026-06-28: crop ONLY the bottom (low-hcnt) garbage, keep the FULL top.
            // HW proof: `(hcnt>247)|(hcnt<8)` gave bottom-correct but top-missing-8 → so hcnt<8 fixes the bottom
            // (KEEP) and hcnt>247 was wrongly cropping 8 good rows off the TOP (the earlier "top perfect" only
            // looked fine because the bottom garbage drew the eye). High edge restored to the natural 255.
            // Visible window = hcnt 8..255 (248 tall): DE narrows at the LOW edge only → screen_rotate latches the
            // smaller hsz → bottom garbage outside the scanned frame, top intact.
            // DIAG-REVERT-2026-06-28: prior lines below (both-ends crop, then top-only crop), uncomment to restore
            // hblank <= (hcnt > 9'd247) | (hcnt < 9'd8);
            hblank <= (hcnt > 9'd257) | (hcnt < 9'd2);   // TOP-EXPAND-2026-06-29: high edge 255->257 = +2 rows at the display-TOP (high hcnt) to restore the 2 truncated BG rows / match MAME. Bottom crop (<2) unchanged. was: (hcnt>9'd255)
            // hblank <= (hcnt > 9'd263) | (hcnt < 9'd8);
        end
    end

    // VBLANK: high when vcnt < 8 or vcnt > 247 (outside visible 8..247)
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            vblank <= (vcnt < 9'd8) | (vcnt > 9'd247);
        end
    end

    // HSYNC: 32-pixel-wide pulse in hblank region [280, 312)
    // Asserted when hcnt is in [280, 311], deasserted at 312
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            hsync <= (hcnt >= 9'd280) & (hcnt < 9'd312);
        end
    end

    // VSYNC: 4-line-wide pulse in vblank region [252, 256)
    // Asserted when vcnt is in [252, 255], deasserted at 256
    always @(posedge clk_sys) begin
        if (ce_pix) begin
            vsync <= (vcnt >= 9'd252) & (vcnt < 9'd256);
        end
    end

    // VSYNC_PULSE: single-cycle strobe on VSYNC rising edge
    // Generate a 1-cycle pulse when VSYNC transitions 0→1
    always @(posedge clk_sys) begin
        if (reset) begin
            vsync_pulse <= 1'b0;
        end else if (ce_pix) begin
            // Rising edge: vcnt == 252 and hcnt == 0 (frame reset point)
            vsync_pulse <= (vcnt == 9'd251) & (hcnt == 9'd383);
        end else begin
            vsync_pulse <= 1'b0;
        end
    end

endmodule
