//============================================================================
//  DECO Cassette clock-enable chain.
//
//  Single 96 MHz PLL output -> six CEs that match the DECO Cassette
//  divider tree (decocass.cpp lines 59-63 + decocass_tape.cpp
//  TAPE_CLOCKRATE).
//
//      MASTER  = 12.000 MHz   = clk_sys / 8   (not exposed; reference)
//      HCLK    =  6.000 MHz   = clk_sys / 16  -> ce_hclk
//      HCLK1   =  3.000 MHz   = clk_sys / 32  -> ce_hclk1
//      HCLK2   =  1.500 MHz   = clk_sys / 64  -> ce_hclk2
//      HCLK4   =    750 kHz   = clk_sys / 128 -> ce_hclk4
//      audio   =    500 kHz   = clk_sys / 192 -> ce_audio  (HCLK / 12)
//      tape    =    4.8 kHz   = clk_sys / 20000 -> ce_tape
//      ce_pix  = ce_hclk      (alias)
//
//  Every CE is one clk_sys cycle wide. No gated clocks.
//============================================================================

module clock_div (
    input  wire clk_sys,        // 96 MHz
    input  wire reset,
    output wire ce_hclk,        //  6.000 MHz
    output wire ce_hclk1,       //  3.000 MHz
    output wire ce_hclk2,       //  1.500 MHz
    output wire ce_hclk4,       //    750 kHz
    output wire ce_audio,       //    500 kHz
    output wire ce_tape,        //    4.8 kHz
    output wire ce_pix          //  alias of ce_hclk
);

    // Free-running 7-bit prescaler -> all hclk* CEs decode from this.
    // Period = 128 clk_sys cycles = 96 MHz / 128 = 750 kHz (matches HCLK4).
    reg [6:0] hcnt;
    always @(posedge clk_sys) begin
        if (reset) hcnt <= 7'd0;
        else       hcnt <= hcnt + 7'd1;
    end

    assign ce_hclk  = (hcnt[3:0] == 4'b1111);
    assign ce_hclk1 = (hcnt[4:0] == 5'b11111);
    assign ce_hclk2 = (hcnt[5:0] == 6'b111111);
    assign ce_hclk4 = (hcnt[6:0] == 7'b1111111);

    // /12 of ce_hclk -> ce_audio (6 MHz / 12 = 500 kHz)
    reg [3:0] adiv;
    always @(posedge clk_sys) begin
        if (reset)
            adiv <= 4'd0;
        else if (ce_hclk)
            adiv <= (adiv == 4'd11) ? 4'd0 : (adiv + 4'd1);
    end
    assign ce_audio = ce_hclk & (adiv == 4'd11);

    // /20000 of clk_sys -> ce_tape (96 MHz / 20000 = 4.8 kHz)
    reg [14:0] tdiv;
    always @(posedge clk_sys) begin
        if (reset)
            tdiv <= 15'd0;
        else
            tdiv <= (tdiv == 15'd19999) ? 15'd0 : (tdiv + 15'd1);
    end
    assign ce_tape = (tdiv == 15'd19999);

    assign ce_pix = ce_hclk;

endmodule
