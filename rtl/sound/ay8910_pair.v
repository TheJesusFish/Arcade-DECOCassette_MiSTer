// DECO Cassette — Two AY-3-8910 (jt49) chips with address/data latch logic.
//
// References:
//  - decocass.cpp lines 142-145: MAME address/data split mapping
//  - rtl/sound/jt49/hdl/jt49.v: jt49 AY-3-8910 reimplementation
//  - rtl/sound/Filters/tp_lpf_light.v: output low-pass filter
//
// The DECO cassette maps AY chip writes via a split address/data pattern:
//   $2000-$2FFF  → AY1 data write
//   $4000-$4FFF  → AY1 address write (latched)
//   $6000-$6FFF  → AY2 data write
//   $8000-$8FFF  → AY2 address write (latched)
//
// Each AY has an internal address register. When the audio CPU:
//  1. Writes to addr-w ($4xxx/$8xxx): latch the address in a register.
//  2. Writes to data-w ($2xxx/$6xxx): drive the jt49 with the latched address
//     for one ce_hclk2 cycle to write the register.
//
// jt49 uses cs_n/wr_n (active low) + addr[3:0]/din[7:0] interface.
// The wrapper translates the DECO latched pattern into jt49 control signals.

module ay8910_pair (
    input  wire        clk_sys,
    input  wire        ce_hclk2,           // 1.5 MHz CE
    input  wire        ce_audio,           // 500 kHz CE (CPU write side)
    input  wire        reset,

    // Bus from audio CPU (decoded chip selects)
    input  wire        ay1_data_we,        // strobed when audio writes $2xxx
    input  wire        ay1_addr_we,        // strobed when audio writes $4xxx
    input  wire        ay2_data_we,        // strobed when audio writes $6xxx
    input  wire        ay2_addr_we,        // strobed when audio writes $8xxx
    input  wire [7:0]  audio_dout,

    output wire [15:0] sound_out           // mixed, signed
);

    // ========================================================================
    // AY1 address latch
    // ========================================================================
    // When audio_cpu writes to $4xxx, latch the address.
    // Persist across multiple ce_hclk2 cycles.

    reg [3:0] ay1_addr_latch;

    always @(posedge clk_sys) begin
        if (reset) begin
            ay1_addr_latch <= 4'h0;
        end else if (ce_audio && ay1_addr_we) begin
            ay1_addr_latch <= audio_dout[3:0];
        end
    end

    // ========================================================================
    // AY2 address latch
    // ========================================================================

    reg [3:0] ay2_addr_latch;

    always @(posedge clk_sys) begin
        if (reset) begin
            ay2_addr_latch <= 4'h0;
        end else if (ce_audio && ay2_addr_we) begin
            ay2_addr_latch <= audio_dout[3:0];
        end
    end

    // ========================================================================
    // Write pulse stretchers and jt49 control
    // ========================================================================
    // The audio_cpu writes are strobed at ce_audio (500 kHz).
    // The jt49 needs to see a write pulse at its input during ce_hclk2 (1.5 MHz).
    //
    // To ensure the jt49 sees the write:
    //  - When ay1_data_we is strobed (at ce_audio), pulse ay1_wr_n low for one
    //    ce_hclk2 cycle. This requires a small state machine or pulse-stretching
    //    logic to bridge the two clock domains (500 kHz -> 1.5 MHz).
    //
    // Strategy: Detect the strobe edge in ce_audio, then latch a pulse flag
    // that gets cleared when ce_hclk2 fires. This ensures at least one ce_hclk2
    // cycle sees the write.

    reg ay1_data_we_r, ay2_data_we_r;
    reg ay1_pulse, ay2_pulse;

    always @(posedge clk_sys) begin
        if (reset) begin
            ay1_data_we_r <= 1'b0;
            ay2_data_we_r <= 1'b0;
            ay1_pulse <= 1'b0;
            ay2_pulse <= 1'b0;
        end else begin
            ay1_data_we_r <= ay1_data_we;
            ay2_data_we_r <= ay2_data_we;

            // Edge detect: rising edge of ay1_data_we sets pulse flag
            if (ce_audio && ay1_data_we && ~ay1_data_we_r) begin
                ay1_pulse <= 1'b1;
            end else if (ce_hclk2) begin
                ay1_pulse <= 1'b0;
            end

            // Same for ay2
            if (ce_audio && ay2_data_we && ~ay2_data_we_r) begin
                ay2_pulse <= 1'b1;
            end else if (ce_hclk2) begin
                ay2_pulse <= 1'b0;
            end
        end
    end

    // ========================================================================
    // jt49 #1 instantiation
    // ========================================================================

    wire [9:0] ay1_sound;
    wire [7:0] ay1_A, ay1_B, ay1_C;

    jt49 #(
        .COMP(3'b000),
        .CLKDIV(3)
    ) ay1 (
        .rst_n    (~reset),
        .clk      (clk_sys),
        .clk_en   (ce_hclk2),
        .addr     (ay1_addr_latch),
        .cs_n     (~ay1_pulse),          // active low: pulse=1 -> cs_n=0
        .wr_n     (~ay1_pulse),          // active low: pulse=1 -> wr_n=0
        .din      (audio_dout),
        .sel      (1'b1),                 // clock not divided by 2
        .dout     (),                     // output not used
        .sound    (ay1_sound),            // [9:0] combined output
        .A        (ay1_A),                // [7:0] linearised channel A
        .B        (ay1_B),
        .C        (ay1_C),
        .sample   (),
        .IOA_in   (8'h00),
        .IOA_out  (),
        .IOB_in   (8'h00),
        .IOB_out  ()
    );

    // ========================================================================
    // jt49 #2 instantiation
    // ========================================================================

    wire [9:0] ay2_sound;
    wire [7:0] ay2_A, ay2_B, ay2_C;

    jt49 #(
        .COMP(3'b000),
        .CLKDIV(3)
    ) ay2 (
        .rst_n    (~reset),
        .clk      (clk_sys),
        .clk_en   (ce_hclk2),
        .addr     (ay2_addr_latch),
        .cs_n     (~ay2_pulse),
        .wr_n     (~ay2_pulse),
        .din      (audio_dout),
        .sel      (1'b1),
        .dout     (),
        .sound    (ay2_sound),
        .A        (ay2_A),
        .B        (ay2_B),
        .C        (ay2_C),
        .sample   (),
        .IOA_in   (8'h00),
        .IOA_out  (),
        .IOB_in   (8'h00),
        .IOB_out  ()
    );

    // ========================================================================
    // Mixing: sum the 10-bit unsigned outputs to 16-bit signed
    // ========================================================================
    // Each jt49 outputs a 10-bit unsigned sample (0 to 1023).
    // Sum both AYs: 0 to 2046 (11-bit unsigned).
    // Subtract offset (1024) to center at zero: -1024 to 1022 (signed).
    // Shift left by 5 to expand to 16-bit range: -32768 to 32704.
    //
    // Formula: sound_mixed = (ay1_sound + ay2_sound - 1024) << 5

    wire [10:0] ay_sum = {1'b0, ay1_sound} + {1'b0, ay2_sound};
    wire [10:0] ay_centered = ay_sum - 11'd1024;
    wire signed [15:0] sound_mixed = {{5{ay_centered[10]}}, ay_centered};  // sign-extend

    // ========================================================================
    // Low-pass filter
    // ========================================================================
    // Apply tp_lpf_light to smooth the raw AY output.

    tp_lpf_light lpf (
        .clk   (clk_sys),
        .reset (reset),
        .in    (sound_mixed),
        .out   (sound_out)
    );

endmodule
