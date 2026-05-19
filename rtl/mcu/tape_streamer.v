// DECO Cassette System — Tape Streamer
// Synthesized implementation of decocass_tape.cpp
//
// Produces 4800 bps serial tape data from a cassette image (256-byte blocks).
// Image contains RAW data bytes; CRC16 is computed on-the-fly in hardware per block.
//
// Mirroring MAME decocass_tape.cpp: maintains clockpos (tape position),
// computes region/byte/bit from clockpos, reads image bytes, applies CRC16,
// and outputs serial stream with framing.

module tape_streamer (
    input  wire        clk_sys,          // 96 MHz system clock
    input  wire        ce_tape,          // 4.8 kHz clock-enable strobe
    input  wire        reset,

    // Tape image read port (SDRAM or BRAM)
    output wire [17:0] image_addr,
    input  wire [7:0]  image_q,

    input  wire [17:0] image_size_bytes,

    // Transport control from MCU
    input  wire        motor_on,
    input  wire        direction,        // 1 = forward, 0 = rewind
    input  wire [1:0]  speed_select,     // 00 stop, 01 normal, 10 fast-fwd, 11 rewind

    // CRC16 table lookup (computed by cassette_loader at ROM-load time)
    output wire [7:0]  crc_addr,
    input  wire [15:0] crc_q,

    // Outputs to MCU
    output wire        tape_data,
    output wire        tape_clock,
    output wire        tape_bot,
    output wire        tape_eot
);

    // =====================================================================
    // Constants from decocass_tape.cpp
    // =====================================================================

    // Tape clock rate: 4800 Hz, thus 2 clocks per bit, 16 per byte
    localparam TAPE_CLOCKRATE       = 4800;
    localparam CLOCKS_PER_BIT       = 2;
    localparam CLOCKS_PER_BYTE      = 16;

    // Convert milliseconds to tape clocks: (ms * 4800 / 1000)
    localparam LEADER_CLOCKS        = 4800;      // 1.0 s
    localparam LEADER_GAP_CLOCKS    = 7200;      // 1.5 s
    localparam BOT_CLOCKS           = 12;        // 2.5 ms
    localparam BOT_GAP_CLOCKS       = 1440;      // 300 ms

    // Region markers (tape clock positions)
    localparam REGION_LEADER_END    = LEADER_CLOCKS;
    localparam REGION_LEADER_GAP_END = REGION_LEADER_END + LEADER_GAP_CLOCKS;
    localparam REGION_BOT_END       = REGION_LEADER_GAP_END + BOT_CLOCKS;
    localparam REGION_BOT_GAP_END   = REGION_BOT_END + BOT_GAP_CLOCKS;

    // Data block structure: 297 bytes per block (from decocass_tape.h)
    // PRE_GAP(34) + LEADIN(1) + HEADER(1) + DATA(256) + CRC_MSB(1) + CRC_LSB(1) +
    // TRAILER(1) + LEADOUT(1) + LONGCLOCK(1) + POSTGAP(34) = 297 bytes
    // Each byte = 16 clock cycles at tape rate
    localparam BYTES_PER_BLOCK      = 297;
    localparam CLOCKS_PER_BLOCK     = BYTES_PER_BLOCK * CLOCKS_PER_BYTE;

    // Byte indices within a block
    localparam BYTE_PRE_GAP_START   = 0;
    localparam BYTE_PRE_GAP_END     = 33;
    localparam BYTE_LEADIN          = 34;
    localparam BYTE_HEADER          = 35;
    localparam BYTE_DATA_START      = 36;
    localparam BYTE_DATA_END        = 291;
    localparam BYTE_CRC_MSB         = 292;
    localparam BYTE_CRC_LSB         = 293;
    localparam BYTE_TRAILER         = 294;
    localparam BYTE_LEADOUT         = 295;
    localparam BYTE_LONGCLOCK       = 296;
    localparam BYTE_POSTGAP_START   = 297;
    localparam BYTE_POSTGAP_END     = 330;

    // =====================================================================
    // State registers
    // =====================================================================

    reg [31:0] clockpos;                // Current tape position (in clock cycles)
    reg [31:0] total_clocks;            // Total clocks for this image
    reg [31:0] num_blocks;              // Number of data blocks

    // Derived from clockpos (combinational)
    wire [31:0] data_region_clocks;
    wire [31:0] dataclock;
    wire [8:0]  byte_offset;
    wire [2:0]  bit_offset;
    wire [7:0]  block_num;

    // Current byte being output
    wire [7:0]  current_byte;

    // CRC table is external (computed by cassette_loader at ROM-load time,
    // stored in `crc16_table_bram` in the wrapper). Drive read address from
    // `block_num`; result comes back via `crc_q` (1-cycle BRAM latency).
    assign crc_addr = block_num;

    // =====================================================================
    // Compute total tape clocks from image size
    // =====================================================================

    always @(posedge clk_sys) begin
        if (reset) begin
            // numblocks = ceil(image_size_bytes / 256)
            // Scan would be at init; for hardware, assume cassette_loader provides length
            num_blocks <= (image_size_bytes + 255) >> 8;

            // Total clocks = header + (blocks * CLOCKS_PER_BLOCK) + trailer
            // Header: LEADER + LEADER_GAP + BOT + BOT_GAP (= REGION_BOT_GAP_END)
            // Trailer: BOT_GAP + EOT + EOT_GAP + TRAILER_GAP + TRAILER (symmetric)
            total_clocks <= REGION_BOT_GAP_END +
                           ((image_size_bytes + 255) >> 8) * CLOCKS_PER_BLOCK +
                           REGION_BOT_GAP_END;  // Symmetric trailer
        end
    end

    // =====================================================================
    // Tape position advance (motor-driven)
    // =====================================================================

    always @(posedge clk_sys) begin
        if (reset) begin
            clockpos <= 0;
        end else if (ce_tape) begin
            if (motor_on) begin
                if (direction) begin
                    // Forward
                    if (clockpos < total_clocks - 1)
                        clockpos <= clockpos + 1;
                end else begin
                    // Rewind
                    if (clockpos > 0)
                        clockpos <= clockpos - 1;
                end
            end
            // Else: motor_on == 0, position holds
        end
    end

    // =====================================================================
    // Combinational: Decode tape position into region/block/byte/bit
    // =====================================================================

    assign data_region_clocks = (clockpos >= REGION_BOT_GAP_END) ?
                                (clockpos - REGION_BOT_GAP_END) : 32'h0;

    assign dataclock = data_region_clocks % CLOCKS_PER_BLOCK;
    assign byte_offset = dataclock / CLOCKS_PER_BYTE;
    assign bit_offset = (dataclock / CLOCKS_PER_BIT) & 3'h7;
    assign block_num = (data_region_clocks / CLOCKS_PER_BLOCK) & 8'hFF;

    // =====================================================================
    // Region detection (mirrors MAME lines 232-275)
    // =====================================================================

    wire [31:0] trailer_start = total_clocks - REGION_BOT_GAP_END;
    wire [31:0] eot_gap_start = total_clocks - REGION_BOT_END;
    wire [31:0] eot_start = total_clocks - BOT_CLOCKS;

    wire in_leader     = (clockpos < REGION_LEADER_END);
    wire in_leader_gap = (clockpos >= REGION_LEADER_END &&
                         clockpos < REGION_LEADER_GAP_END);
    wire in_bot        = (clockpos >= REGION_LEADER_GAP_END &&
                         clockpos < REGION_BOT_END);
    wire in_bot_gap    = (clockpos >= REGION_BOT_END &&
                         clockpos < REGION_BOT_GAP_END);

    wire in_trailer     = (clockpos >= trailer_start);
    wire in_eot_gap     = (clockpos >= eot_gap_start && clockpos < trailer_start);
    wire in_eot         = (clockpos >= eot_start && clockpos < eot_gap_start);

    wire in_data        = !in_leader && !in_leader_gap && !in_bot && !in_bot_gap &&
                         !in_trailer && !in_eot_gap && !in_eot;

    // =====================================================================
    // Image read address (combinational, no buffering)
    // For DATA region, read from image based on block + data offset
    // =====================================================================

    assign image_addr = (in_data && byte_offset >= BYTE_DATA_START &&
                        byte_offset <= BYTE_DATA_END) ?
                        ({block_num, 8'h00} + (byte_offset - BYTE_DATA_START)) :
                        18'h0;

    // =====================================================================
    // Current byte value selection
    // Mirrors MAME get_status_bits() logic
    // =====================================================================

    assign current_byte =
        in_leader || in_leader_gap || in_bot_gap ||
        in_eot_gap || in_trailer || in_eot ? 8'h00 :
        in_bot || in_eot ? 8'h00 :
        (byte_offset >= BYTE_PRE_GAP_START && byte_offset <= BYTE_PRE_GAP_END) ? 8'h00 :
        (byte_offset == BYTE_LEADIN) ? 8'h00 :
        (byte_offset == BYTE_HEADER) ? 8'hAA :
        (byte_offset >= BYTE_DATA_START && byte_offset <= BYTE_DATA_END) ? image_q :
        (byte_offset == BYTE_CRC_MSB) ? crc_q[15:8] :
        (byte_offset == BYTE_CRC_LSB) ? crc_q[7:0] :
        (byte_offset == BYTE_TRAILER) ? 8'hAA :
        (byte_offset == BYTE_LEADOUT) ? 8'h00 :
        (byte_offset == BYTE_LONGCLOCK) ? 8'h00 :
        (byte_offset >= BYTE_POSTGAP_START && byte_offset <= BYTE_POSTGAP_END) ? 8'h00 :
        8'h00;

    // =====================================================================
    // Output: tape_data (serial, MSB-first per MAME line 334)
    // =====================================================================

    assign tape_data = current_byte[bit_offset];

    // =====================================================================
    // Output: tape_clock (active high during clocked regions, MAME line 304-315)
    // =====================================================================

    wire clk_region_active = (in_data &&
                             byte_offset >= BYTE_LEADIN &&
                             byte_offset <= BYTE_LONGCLOCK);

    wire clk_bit = (data_region_clocks & 32'h1) ? 1'b0 : 1'b1;  // MAME line 305

    assign tape_clock = (byte_offset == BYTE_LONGCLOCK) ? 1'b1 :  // LONGCLOCK holds high
                       (clk_region_active) ? ~clk_bit :           // Inverted alternating clock
                       1'b0;                                       // Idle

    // =====================================================================
    // Output: tape_bot and tape_eot (hole sense signals)
    // Mirrors MAME get_status_bits() lines 292-294
    // =====================================================================

    assign tape_bot = in_leader || in_bot || in_eot || in_trailer;

    assign tape_eot = in_eot_gap || in_eot;

    // CRC table is populated externally by cassette_loader.

endmodule
