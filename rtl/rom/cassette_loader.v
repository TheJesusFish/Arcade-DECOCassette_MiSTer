//============================================================================
//  DECO Cassette System — Cassette Image Loader + CRC16 Precompute
//
//  Stream the cassette image from hps_io into BRAM during ioctl_download.
//  Compute the per-block CRC16 as bytes stream past and write each block's
//  CRC into a small lookup BRAM.
//
//  CRC16 implementation per MAME `decocass_tape.cpp:130-147`
//  (`tape_crc16_byte`):
//      for (i = 0; i < 8; i++) {
//          crc = (crc >> 1) | (crc << 15);             // rotate right
//          crc ^= (data << 7) & 0x80;                  // bit 0 of data -> bit 7
//          if (crc & 0x80) crc ^= 0x0120;
//      }
//  Note this is DECOCassette's non-standard CRC: only bit 0 of each byte
//  actually contributes.
//
//  Each cassette block is 256 data bytes. After every 256 bytes, the running
//  CRC is stored in `crc_table` and the accumulator is reset.
//
//  Simplification vs. MAME: MAME stores a "testval" via brute-force search
//  (such that crc16(crc16(running_crc, testval>>8), testval) == 0).
//  We store the raw running CRC instead. If BIOS compares CRC bytes directly,
//  this works; if BIOS verifies final-CRC = 0, this won't (but no worse than
//  the previous placeholder=0).
//============================================================================

`timescale 1 ps / 1 ps

module cassette_loader (
    input  wire        clk_sys,
    input  wire        ioctl_download,
    input  wire        ioctl_wr,
    input  wire [24:0] ioctl_addr,
    input  wire [7:0]  ioctl_dout,

    output reg  [15:0] bram_addr,
    output reg  [7:0]  bram_dout,
    output reg         bram_we,

    // CRC16 table write interface (256 blocks × 16 bits)
    output reg  [7:0]  crc_table_addr,
    output reg  [15:0] crc_table_data,
    output reg         crc_table_we,

    output reg  [17:0] image_size_bytes
);

    wire [24:0] addr = ioctl_addr;
    wire [7:0]  data = ioctl_dout;

    wire sel_cassette = (addr >= 25'h03000) && (addr <= 25'h3FFFF);
    wire [24:0] cassette_addr_rel = addr - 25'h03000;
    wire is_first_byte = sel_cassette && (cassette_addr_rel == 25'd0);

    // CRC16 step matching MAME `tape_crc16_byte` exactly.
    function [15:0] tape_crc16_byte;
        input [15:0] crc;
        input [7:0]  d;
        integer i;
        reg [15:0] r;
        begin
            r = crc;
            for (i = 0; i < 8; i = i + 1) begin
                r = {r[0], r[15:1]};
                r = r ^ (d[0] ? 16'h0080 : 16'h0000);
                if (r[7])
                    r = r ^ 16'h0120;
            end
            tape_crc16_byte = r;
        end
    endfunction

    reg [15:0] crc_acc;
    reg [7:0]  byte_in_block;
    reg [7:0]  current_block;

    always @(posedge clk_sys) begin
        bram_we      <= 1'b0;
        crc_table_we <= 1'b0;

        if (ioctl_download && ioctl_wr && sel_cassette) begin
            bram_we    <= 1'b1;
            bram_addr  <= cassette_addr_rel[15:0];
            bram_dout  <= data;

            if (is_first_byte) begin
                image_size_bytes <= 18'd1;
                crc_acc          <= tape_crc16_byte(16'h0000, data);
                byte_in_block    <= 8'd1;
                current_block    <= 8'd0;
            end else begin
                image_size_bytes <= image_size_bytes + 18'd1;
                if (byte_in_block == 8'd255) begin
                    crc_table_we   <= 1'b1;
                    crc_table_addr <= current_block;
                    crc_table_data <= tape_crc16_byte(crc_acc, data);
                    crc_acc        <= 16'h0000;
                    byte_in_block  <= 8'd0;
                    current_block  <= current_block + 8'd1;
                end else begin
                    crc_acc        <= tape_crc16_byte(crc_acc, data);
                    byte_in_block  <= byte_in_block + 8'd1;
                end
            end
        end
    end

    initial begin
        bram_we          = 1'b0;
        bram_addr        = 16'd0;
        bram_dout        = 8'd0;
        image_size_bytes = 18'd0;
        crc_table_we     = 1'b0;
        crc_table_addr   = 8'd0;
        crc_table_data   = 16'd0;
        crc_acc          = 16'h0000;
        byte_in_block    = 8'd0;
        current_block    = 8'd0;
    end

endmodule
