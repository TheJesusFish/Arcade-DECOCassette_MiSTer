//============================================================================
// DECO Cassette Sound Latches — bidirectional main ↔ audio communication
//
// This module implements the sound command and data latches for communication
// between the main CPU and audio CPU, plus the IRQ/acknowledge handshake.
//
// References:
//  - decocass_m.cpp lines 67-108: sound command/data/ack handlers
//  - Task 14: detailed behavior specification
//  - audio_cpu.v: produces sound_from_main_re and sound_to_main_we strobes
//
// Behavior:
//  Main → Audio (via $E414 write):
//    • Latch command byte into soundlatch
//    • Set sound_ack bit 7 (command pending)
//    • Clear sound_ack bit 6 (data ready)
//    • Assert audio_irq (level-triggered, held high until $A000 read)
//
//  Audio reads $A000:
//    • Return latched command
//    • Deassert audio_irq (level low)
//    • Clear sound_ack bit 7
//
//  Audio → Main (via $C000 write):
//    • Latch response byte into soundlatch2
//    • Set sound_ack bit 6 (data ready)
//
//  Main reads $E700:
//    • Return latched response data
//
//  Main reads $E701:
//    • Return sound_ack register (D7=command pending, D6=data ready)
//
// Clock domain:
//  Both sides operate on clk_sys with separate clock enables (ce_main, ce_audio).
//  Main and audio strobe inputs are already gated by their respective CE signals,
//  so updates are synchronous on clk_sys posedge when strobes assert.
//============================================================================

module sound_latches (
    input  wire        clk_sys,
    input  wire        reset,

    // Main side (CE'd at ce_hclk4 = 750 kHz)
    input  wire        ce_main,             // gating signal (not strictly required if strobes already gated)
    input  wire        main_we_e414,        // main writing $E414 (gated by ce_main)
    input  wire        main_re_e700,        // main reading $E700 (gated by ce_main)
    input  wire        main_re_e701,        // main reading $E701 (gated by ce_main)
    input  wire [7:0]  main_dout,           // data from main CPU ($E414 write)
    output reg  [7:0]  main_din_e700,       // data to main from audio ($E700 read, soundlatch2)
    output reg  [7:0]  main_din_e701,       // data to main ack/status ($E701 read, sound_ack)

    // Audio side (CE'd at ce_audio = 500 kHz)
    input  wire        ce_audio,            // gating signal (not strictly required if strobes already gated)
    input  wire        audio_we_c000,       // audio writing $C000 (gated by ce_audio)
    input  wire        audio_re_a000,       // audio reading $A000 (gated by ce_audio)
    input  wire [7:0]  audio_dout,          // data from audio CPU ($C000 write)
    output reg  [7:0]  audio_din_a000,      // data to audio from main ($A000 read, soundlatch)

    output reg         audio_irq            // active-high; asserted by main_we_e414, deasserted by audio_re_a000
);

    // ========================================================================
    // State registers
    // ========================================================================

    reg [7:0] soundlatch;      // Main → Audio command
    reg [7:0] soundlatch2;     // Audio → Main response
    reg [7:0] sound_ack;       // Handshake register: D7=command pending, D6=data ready

    // ========================================================================
    // Combinational read outputs
    // ========================================================================

    always @* begin
        // $E700: return soundlatch2 (audio → main data)
        main_din_e700 = soundlatch2;

        // $E701: return sound_ack register
        // AUDIO-ACK-BYPASS-2026-06-10: force D7 (sound-cmd-pending) = 0 so the BIOS load loops
        // (`bit $e701 / bmi` at cassette $F104 and darksoft $F9BF) DON'T hang waiting for the audio CPU
        // to ACK a sound command — our audio CPU never consumes $A000, so D7 stays stuck = the universal
        // "Loading..." freeze (block-15 cassette + every darksoft game). PROVES the root + gives playable
        // (silent) loads. DIAG-REVERT-2026-06-10: restore `main_din_e701 = sound_ack;` once audio actually acks.
        // AUDIO-ACK-REAL-2026-06-11: override REMOVED — the audio CPU now executes cleanly (AUDIO-BRAM-READ-FIX)
        // and reads $A000 to clear D7 reliably, so the REAL ack works. The bypass wasn't just cosmetic: forcing
        // D7=0 BROKE in-game sound. The main BIOS streams the audio engine to the audio CPU and waits on D7
        // before EVERY byte (bios.dasm $F0D9/$F0EE/$F104/$F11E: `bit $e701 / bmi`); with D7 faked to 0 it never
        // waited and blasted the download -> dropped nibbles -> corrupt RAM engine -> NMI never armed -> SILENT.
        // DIAG-REVERT-2026-06-11: to restore the bypass, swap the two lines below.
        // main_din_e701 = {1'b0, sound_ack[6:0]};     // AUDIO-ACK-BYPASS (D7 forced 0) — was breaking sound DL
        main_din_e701 = sound_ack;                      // REAL ack (D7 now cleared by the audio CPU's $A000 read)

        // $A000: return soundlatch (main → audio command)
        audio_din_a000 = soundlatch;
    end

    // ========================================================================
    // Sequential update of latches and IRQ
    // ========================================================================

    always @(posedge clk_sys) begin
        if (reset) begin
            soundlatch    <= 8'h00;
            soundlatch2   <= 8'h00;
            sound_ack     <= 8'h00;
            audio_irq     <= 1'b0;
        end else begin
            // Main writes $E414: write command to soundlatch
            // (decocass_m.cpp lines 67-75: decocass_sound_command_w)
            if (main_we_e414) begin
                soundlatch  <= main_dout;
                sound_ack   <= (sound_ack | 8'h80) & 8'hBF;  // set D7, clear D6
                audio_irq   <= 1'b1;
            end

            // Audio reads $A000: clear audio_irq and clear sound_ack D7
            // (decocass_m.cpp lines 98-108: decocass_sound_command_r)
            if (audio_re_a000) begin
                audio_irq <= 1'b0;
                sound_ack <= sound_ack & 8'h7F;  // clear D7
            end

            // Audio writes $C000: write response to soundlatch2, set sound_ack D6
            // (decocass_m.cpp lines 91-96: decocass_sound_data_w)
            if (audio_we_c000) begin
                soundlatch2 <= audio_dout;
                sound_ack   <= sound_ack | 8'h40;  // set D6
            end
        end
    end

endmodule
