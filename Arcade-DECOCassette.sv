//============================================================================
//  Arcade: DECO Cassette System (Data East, 1980-1985)
//
//  Targets: Lock'n'Chase, Burger Time, and the rest of the supported
//  cassette catalogue (~58 sets — see mra/).
//
//  Port to MiSTer
//  Copyright (C) 2026
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign FB_FORCE_BLANK = '0;

assign VGA_F1 = '0;
assign VGA_SCALER = '0;
assign VGA_DISABLE = '0;
assign HDMI_FREEZE = '0;
assign HDMI_BLACKOUT = '0;
assign HDMI_BOB_DEINT = '0;

assign AUDIO_MIX = '0;

assign LED_DISK = '0;
assign LED_POWER = '0;
// DIAGNOSTIC: LED_USER blinks if game_id==5. Steady on if CRTC was written.
// assign LED_USER = dbg_crtc_hit ? 1'b1 : dbg_cpu_active;
assign BUTTONS = '0;

// Screen is ROT270 (vertical monitor). Aspect ratio from status[1:0]
// (0=3:4 original, 1=native)
wire aspect_wide = status[1];
assign VIDEO_ARX = aspect_wide ? 12'd4 : 12'd3;
assign VIDEO_ARY = aspect_wide ? 12'd3 : 12'd4;

`include "build_id.v"
localparam CONF_STR = {
	"DECOCassette;;",
	"O[1],Aspect ratio,3:4,Original;",
	"O[2],Orientation,Vertical,Horizontal;",
	"-;",
	"R0,Reset;",
	"J1,Button 1,Coin,Start 1P,Start 2P,Pause;",
	"jn,A,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////
//
// Single 96 MHz PLL output -> clk_sys. All DECO Cassette CEs are
// derived in clock_div (task 04).
//
// IMPORTANT: rtl/pll/pll_0002.v must be regenerated in the Quartus
// PLL Megafunction wizard so outclk_0 = 96.0 MHz (8 x 12 MHz master).
// Until that's done, the build compiles but timing is wrong.

wire clk_sys;
wire pll_locked;

pll pll
(
    .refclk   (CLK_50M),
    .rst      (1'b0),
    .outclk_0 (clk_sys),
    .locked   (pll_locked)
);

// Alias for legacy port names in screen_rotate / arcade_video below:
wire clk_vid = clk_sys;

// DECO Cassette clock-enable chain (task 04)
wire ce_hclk;     //  6.000 MHz   (pixel CE, 8041 CE)
wire ce_hclk1;    //  3.000 MHz
wire ce_hclk2;    //  1.500 MHz   (AY-3-8910 x2)
wire ce_hclk4;    //    750 kHz   (DECO-222 main CPU)
wire ce_audio;    //    500 kHz   (audio M6502)
wire ce_tape;     //    4.8 kHz   (cassette streamer)
wire ce_pix;      //  alias of ce_hclk

clock_div clock_div_inst (
    .clk_sys  (clk_sys),
    .reset    (~pll_locked),
    .ce_hclk  (ce_hclk),
    .ce_hclk1 (ce_hclk1),
    .ce_hclk2 (ce_hclk2),
    .ce_hclk4 (ce_hclk4),
    .ce_audio (ce_audio),
    .ce_tape  (ce_tape),
    .ce_pix   (ce_pix)
);

///////////////////////////////////////////////////
// Intermediate bus declarations for interconnect
///////////////////////////////////////////////////

// Graphics subsystem address/data buses (ports B from dual-port RAMs)
wire [9:0]  fgvram_addr_gfx, colram_addr_gfx;
wire [10:0] tilram_addr_gfx;
wire [9:0]  objram_addr_gfx;
wire [7:0]  fgvram_q_gfx, colram_q_gfx;
wire [7:0]  tilram_q_gfx, objram_q_gfx;

// E5xx dongle composite data
wire [7:0]  e5xx_dongle;
wire [7:0]  e5xx_to_cpu;   // DONGLE BYPASS FIX 2026-05-30 (assigned near dongle_mux below)

// BIOS ROM interface (CPU side)
wire [7:0]  bios_dout_cpu;
wire        bios_we_cpu_int;

// Video signals
wire        video_vblank, video_hsync, video_vsync, video_hblank;

// Video timing counters (fanout to all video layers)
wire [8:0]  hcnt, vcnt;

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        video_rotated;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joystick_r_analog_0;   // right analog stick: [15:8]=Y signed, [7:0]=X signed
wire [10:0] ps2_key;

wire [21:0] gamma_bus;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.status(status),
	.status_menumask({direct_video}),

	.forced_scandoubler(forced_scandoubler),
	.video_rotated(video_rotated),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_r_analog_0(joystick_r_analog_0),
	.ps2_key(ps2_key)
);

assign ioctl_upload_req = 1'b0;
assign ioctl_din        = 8'd0;

// =========================================================================
// Phase 03: stubbed core. Every block below gets reworked in later phases.
//
//   clocks      -> task 04
//   reset/DIP   -> task 26
//   pause       -> already wired (kept)
//   video       -> tasks 07-11
//   audio       -> tasks 12-14
//   inputs      -> task 23
//   ROM/MRA     -> task 25
// =========================================================================

// =========================================================================
// INTEGRATED CORE — WAVE 6 INTEGRATION PASS
// =========================================================================

// Reset and DIP handling
wire reset = (RESET | status[0] | buttons[1] | ioctl_download);

reg [7:0] sw[8];
always @(posedge clk_sys)
	if (ioctl_wr && (ioctl_index==8'd254) && !ioctl_addr[24:3])
		sw[ioctl_addr[2:0]] <= ioctl_dout;

// Extract metadata from ROM loader
wire [7:0] dongle_type_byte;
wire [7:0] game_id_byte;
wire [7:0] swap_mode_byte;
wire [7:0] game_id   = game_id_byte;         // 2026-05-30: full 8-bit = DECO release number (was [3:0])
wire [3:0] swap_mode = swap_mode_byte[3:0];  // From metadata $02E02 (was sw[1])
wire [2:0] dongle_type = dongle_type_byte[2:0];

// =========================================================================
// ROM LOADER (task 25)
// =========================================================================
wire        bios_we_rom, abios_we_rom, mcurom_we;
wire [11:0] bios_addr_rom;
wire [10:0] abios_addr_rom;
wire [9:0]  mcurom_addr;
wire [7:0]  bios_dout_rom, abios_dout_rom, mcurom_dout;
wire        palprom_we;
wire [7:0]  palprom_addr, palprom_dout;
wire        dongleprom_we;
wire [11:0] dongleprom_addr;
wire [7:0]  dongleprom_dout;

rom_loader rom_loader_inst (
	.clk_sys               (clk_sys),
	.ioctl_download        (ioctl_download),
	.ioctl_wr              (ioctl_wr),
	.ioctl_addr            (ioctl_addr),
	.ioctl_dout            (ioctl_dout),
	.ioctl_index           (ioctl_index),
	.bios_we               (bios_we_rom),
	.bios_addr             (bios_addr_rom),
	.bios_dout             (bios_dout_rom),
	.abios_we              (abios_we_rom),
	.abios_addr            (abios_addr_rom),
	.abios_dout            (abios_dout_rom),
	.mcurom_we             (mcurom_we),
	.mcurom_addr           (mcurom_addr),
	.mcurom_dout           (mcurom_dout),
	.palprom_we            (palprom_we),
	.palprom_addr          (palprom_addr),
	.palprom_dout          (palprom_dout),
	.dongleprom_we         (dongleprom_we),
	.dongleprom_addr       (dongleprom_addr),
	.dongleprom_dout       (dongleprom_dout),
	.metadata_dongle_type  (dongle_type_byte),
	.metadata_game_id      (game_id_byte),
	.metadata_swap_mode    (swap_mode_byte)
);

// =========================================================================
// MEMORY: BIOS ROM (main CPU $F000-$FFFF, 4 KB)
// =========================================================================
wire [11:0] bios_addr_cpu;
wire [11:0] bios_addr_cpu_dec;     // address from decocass (CPU-side)
wire        bios_we_cpu;
wire [7:0]  bios_dw_cpu, bios_q;

spram #(.address_width(12), .data_width(8)) bios_rom (
	.clock     (clk_sys),
	.enable    (1'b1),
	.address   (bios_addr_cpu),
	.data      (bios_dw_cpu),
	.wren      (bios_we_cpu),
	.q         (bios_q)
);

// ROM loader and CPU write arbitration for BIOS
assign bios_addr_cpu = bios_we_rom ? bios_addr_rom : bios_addr_cpu_dec;
assign bios_we_cpu   = bios_we_rom | (bios_we_cpu_int & ce_hclk4);
assign bios_dw_cpu   = bios_we_rom ? bios_dout_rom : bios_dout_cpu;

// =========================================================================
// MEMORY: Audio CPU BIOS ROM ($F800-$FFFF, 2 KB)
// =========================================================================
wire [10:0] abios_addr_audio;
wire [7:0]  abios_q;

spram #(.address_width(11), .data_width(8)) abios_rom (
	.clock     (clk_sys),
	.enable    (1'b1),
	.address   (abios_addr_audio),
	.data      (abios_dout_rom),
	.wren      (abios_we_rom),
	.q         (abios_q)
);

// =========================================================================
// MEMORY: Work RAM (main CPU $0000-$5FFF, 24 KB = 15-bit address)
// =========================================================================
wire [14:0] ram_addr_cpu;
wire        ram_we_cpu;
wire [7:0]  ram_dw_cpu, ram_q;

spram #(.address_width(15), .data_width(8)) work_ram (
	.clock     (clk_sys),
	.enable    (1'b1),
	.address   (ram_addr_cpu),
	.data      (ram_dw_cpu),
	.wren      (ram_we_cpu),
	.q         (ram_q)
);

// =========================================================================
// MEMORY: Charram CPU-readback path ($6000-$BFFF, 24 KB total — 3 planes × 8 KB)
// =========================================================================
// 2026-05-17 — Render-side charram lives in video_fg.v as 3 separate planes
// (per MAME `charlayout` 3bpp). This SPRAM is the *CPU readback* copy for
// when BIOS reads from $6000-$BFFF. It aliases all 3 planes into one 8 KB
// window — BIOS doesn't seem to read charram back in early boot, so this is
// acceptable for now. A proper fix would split this into 3 SPRAMs too.
wire [12:0] charram_addr_cpu;
wire        charram_we_p0, charram_we_p1, charram_we_p2;
wire        charram_we_any = charram_we_p0 | charram_we_p1 | charram_we_p2;
wire [7:0]  charram_dw_cpu, charram_q;

spram #(.address_width(13), .data_width(8)) charram (
	.clock     (clk_sys),
	.enable    (1'b1),
	.address   (charram_addr_cpu),
	.data      (charram_dw_cpu),
	.wren      (charram_we_any),
	.q         (charram_q)
);

// =========================================================================
// MEMORY: FG Video RAM ($C000-$C3FF + mirror $C800-$CBFF, 1 KB = 10-bit)
// =========================================================================
wire [9:0]  fgvram_addr_cpu;
wire        fgvram_we_cpu;
wire [7:0]  fgvram_dw_cpu, fgvram_q;

dpram #(.address_width(10), .data_width(8)) fgvram (
	.clock_a   (clk_sys),
	.enable_a  (1'b1),
	.address_a (fgvram_addr_cpu),
	.data_a    (fgvram_dw_cpu),
	.wren_a    (fgvram_we_cpu),
	.q_a       (fgvram_q),
	.clock_b   (clk_sys),
	.enable_b  (1'b1),
	.address_b (fgvram_addr_gfx),
	.data_b    (8'h00),
	.wren_b    (1'b0),
	.q_b       (fgvram_q_gfx)
);

// =========================================================================
// MEMORY: Color RAM ($C400-$C7FF + mirror $CC00-$CFFF, 1 KB = 10-bit)
// =========================================================================
wire [9:0]  colram_addr_cpu;
wire        colram_we_cpu;
wire [7:0]  colram_dw_cpu, colram_q;

dpram #(.address_width(10), .data_width(8)) colram (
	.clock_a   (clk_sys),
	.enable_a  (1'b1),
	.address_a (colram_addr_cpu),
	.data_a    (colram_dw_cpu),
	.wren_a    (colram_we_cpu),
	.q_a       (colram_q),
	.clock_b   (clk_sys),
	.enable_b  (1'b1),
	.address_b (colram_addr_gfx),
	.data_b    (8'h00),
	.wren_b    (1'b0),
	.q_b       (colram_q_gfx)
);

// =========================================================================
// MEMORY: Tileram ($D000-$D7FF, 2 KB = 11-bit)
// =========================================================================
wire [10:0] tilram_addr_cpu;
wire        tilram_we_cpu;
wire [7:0]  tilram_dw_cpu, tilram_q;

dpram #(.address_width(11), .data_width(8)) tilram (
	.clock_a   (clk_sys),
	.enable_a  (1'b1),
	.address_a (tilram_addr_cpu),
	.data_a    (tilram_dw_cpu),
	.wren_a    (tilram_we_cpu),
	.q_a       (tilram_q),
	.clock_b   (clk_sys),
	.enable_b  (1'b1),
	.address_b (tilram_addr_gfx),
	.data_b    (8'h00),
	.wren_b    (1'b0),
	.q_b       (tilram_q_gfx)
);

// =========================================================================
// MEMORY: Objectram ($D800-$DBFF, 1 KB = 10-bit)
// =========================================================================
wire [9:0]  objram_addr_cpu;
wire        objram_we_cpu;
wire [7:0]  objram_dw_cpu, objram_q;

dpram #(.address_width(10), .data_width(8)) objram (
	.clock_a   (clk_sys),
	.enable_a  (1'b1),
	.address_a (objram_addr_cpu),
	.data_a    (objram_dw_cpu),
	.wren_a    (objram_we_cpu),
	.q_a       (objram_q),
	.clock_b   (clk_sys),
	.enable_b  (1'b1),
	.address_b (objram_addr_gfx),
	.data_b    (8'h00),
	.wren_b    (1'b0),
	.q_b       (objram_q_gfx)
);

// =========================================================================
// MEMORY: Palette RAM ($E000-$E0FF, 256 bytes = 8-bit)
// =========================================================================
wire [7:0]  palram_addr_cpu;
wire        palram_we_cpu;
wire [7:0]  palram_dw_cpu, palram_q;
wire [7:0]  palram_addr_video;
wire [7:0]  palram_q_video;

dpram #(.address_width(8), .data_width(8)) palram (
	.clock_a   (clk_sys),
	.enable_a  (1'b1),
	.address_a (palram_addr_cpu),
	.data_a    (palram_dw_cpu),
	.wren_a    (palram_we_cpu),
	.q_a       (palram_q),
	.clock_b   (clk_sys),
	.enable_b  (1'b1),
	.address_b (palram_addr_video),
	.data_b    (8'h00),
	.wren_b    (1'b0),
	.q_b       (palram_q_video)
);

// =========================================================================
// MAIN CPU: DECO-222 @ 750 kHz (ce_hclk4 = HCLK4, per MAME decocass.cpp:1018)
// =========================================================================
wire [15:0] cpu_addr;
wire [7:0]  cpu_dout;
wire        cpu_rw_n, cpu_sync;

// Write strobes from decocass
wire cpu_we_ram, cpu_we_charram, cpu_we_fgvram, cpu_we_colram;
wire cpu_we_tilram, cpu_we_objram, cpu_we_palram;
wire cpu_we_e3xx, cpu_we_e4xx, cpu_we_e414, cpu_we_e5xx, cpu_re_e5xx;
wire cpu_we_e6xx, cpu_we_e7xx, cpu_re_e700, cpu_re_e701;

// Control register outputs
wire [7:0] mode_set_reg, back_h_shift_reg, back_vl_shift_reg, back_vr_shift_reg;
wire [7:0] part_h_shift_reg, part_v_shift_reg, color_center_bot_reg;
wire [7:0] center_h_shift_space_reg, center_v_shift_reg, coin_counter_reg, nmi_reset_reg;

// Main CPU memmap decoder
decocass decocass_inst (
	.clk_sys           (clk_sys),
	.ce_main           (ce_hclk4),        // 750 kHz CPU clock (HCLK4 per MAME decocass.cpp:1018)
	.reset             (reset),
	.cpu_addr          (cpu_addr),
	.cpu_dout          (cpu_dout),
	.cpu_rw_n          (cpu_rw_n),
	.cpu_sync          (cpu_sync),
	.cpu_we_ram        (cpu_we_ram),
	.cpu_we_charram    (cpu_we_charram),
	.cpu_we_fgvram     (cpu_we_fgvram),
	.cpu_we_colram     (cpu_we_colram),
	.cpu_we_tilram     (cpu_we_tilram),
	.cpu_we_objram     (cpu_we_objram),
	.cpu_we_palram     (cpu_we_palram),
	.cpu_we_e3xx       (cpu_we_e3xx),
	.cpu_we_e4xx       (cpu_we_e4xx),
	.cpu_we_e414       (cpu_we_e414),
	.cpu_we_e5xx       (cpu_we_e5xx),
	.cpu_re_e5xx       (cpu_re_e5xx),
	.cpu_we_e6xx       (cpu_we_e6xx),
	.cpu_we_e7xx       (cpu_we_e7xx),
	.cpu_re_e700       (cpu_re_e700),
	.cpu_re_e701       (cpu_re_e701),
	.sound_data        (sound_data),
	.sound_ack         (sound_ack),
	.e5xx_dongle_q     (e5xx_to_cpu),
	.input_q           (input_q),
	.bios_q            (bios_q),
	.ram_q             (ram_q),
	.charram_q         (charram_q),
	.fgvram_q          (fgvram_q),
	.colram_q          (colram_q),
	.tilram_q          (tilram_q),
	.objram_q          (objram_q),
	.palram_q          (palram_q),
	.dsw1              (sw[2]),
	.dsw2              (sw[3]),
	.vblank            (video_vblank),
	.coin_in           (joystick_0[14] | joystick_1[14]),  // P1 or P2 coin → main-CPU NMI (MAME decocass_m.cpp:155-159)
	.ram_addr_w        (ram_addr_cpu),
	.ram_we_w          (ram_we_cpu),
	.ram_dw            (ram_dw_cpu),
	.charram_addr_w    (charram_addr_cpu),
	.charram_we_p0     (charram_we_p0),
	.charram_we_p1     (charram_we_p1),
	.charram_we_p2     (charram_we_p2),
	.charram_dw        (charram_dw_cpu),
	.fgvram_addr_w     (fgvram_addr_cpu),
	.fgvram_we_w       (fgvram_we_cpu),
	.fgvram_dw         (fgvram_dw_cpu),
	.colram_addr_w     (colram_addr_cpu),
	.colram_we_w       (colram_we_cpu),
	.colram_dw         (colram_dw_cpu),
	.tilram_addr_w     (tilram_addr_cpu),
	.tilram_we_w       (tilram_we_cpu),
	.tilram_dw         (tilram_dw_cpu),
	.objram_addr_w     (objram_addr_cpu),
	.objram_we_w       (objram_we_cpu),
	.objram_dw         (objram_dw_cpu),
	.palram_addr_w     (palram_addr_cpu),
	.palram_we_w       (palram_we_cpu),
	.palram_dw         (palram_dw_cpu),
	.bios_addr_w       (bios_addr_cpu_dec),
	.bios_we_w         (bios_we_cpu_int),
	.bios_dw           (bios_dout_cpu),
	.mode_set_reg      (mode_set_reg),
	.back_h_shift_reg  (back_h_shift_reg),
	.back_vl_shift_reg (back_vl_shift_reg),
	.back_vr_shift_reg (back_vr_shift_reg),
	.part_h_shift_reg  (part_h_shift_reg),
	.part_v_shift_reg  (part_v_shift_reg),
	.color_center_bot_reg (color_center_bot_reg),
	.center_h_shift_space_reg (center_h_shift_space_reg),
	.center_v_shift_reg    (center_v_shift_reg),
	.coin_counter_reg      (coin_counter_reg),
	.nmi_reset_reg         (nmi_reset_reg)
);

// =========================================================================
// MCU: i8041 + Program Memory + Tape Interface (tasks 15-17)
// =========================================================================
wire [7:0]  mcu_p1_out, mcu_p2_out, mcu_p1_in, mcu_p2_in;
wire        mcu_t0, mcu_t1;
wire [7:0]  mcu_host_dout;
wire [7:0]  mcu_host_sts;       // DBBSTS exposure 2026-05-30: real STATUS reg from the i8041 core
wire        mcu_sync_o;         // DIAG-REVERT-2026-05-30: MCU ALE/sync strobe — toggles iff the MCU executes
wire        mcu_host_dout_oe;
wire        tape_motor_on, tape_direction;
wire [1:0]  tape_speed_select;
wire        tape_data, tape_clock, tape_bot, tape_eot;

// i8041 MCU + program memory
i8041_top i8041_inst (
	.clk_sys         (clk_sys),
	.ce_hclk         (ce_hclk),
	.reset_n         (~reset),
	.cs_n            (mcu_cs_n),
	.rd_n            (mcu_rd_n),
	.wr_n            (mcu_wr_n),
	.a0              (mcu_a0),
	.host_din        (mcu_host_din),
	.host_dout       (mcu_host_dout),
	.host_sts        (mcu_host_sts),       // DBBSTS exposure 2026-05-30
	.host_dout_oe    (mcu_host_dout_oe),
	.sync_o          (mcu_sync_o),  // DIAG-REVERT-2026-05-30: was () — MCU execution liveness probe
	.t0_i            (mcu_t0),
	.t1_i            (mcu_t1),
	.p1_i            (mcu_p1_in),
	.p1_o            (mcu_p1_out),
	.p1_low_imp      (),
	.p2_i            (mcu_p2_in),
	.p2_o            (mcu_p2_out),
	.p2l_low_imp     (),
	.p2h_low_imp     (),
	.prog_n          (),
	.rom_we          (mcurom_we),
	.rom_addr_w      (mcurom_addr),
	.rom_data_w      (mcurom_dout)
);

// MCU ↔ Tape ↔ Main CPU interface
wire [7:0]  dongle_addr_lo;
wire        dongle_re, dongle_we;
wire [7:0]  dongle_dout;
wire [3:0]  dongle_din_low4;    // legacy 4-bit nibble (mcu_tape_iface still uses it)
wire [7:0]  dongle_din_full;    // 2026-05-18 — full 8-bit dongle output (per MAME)
wire        mcu_cs_n, mcu_rd_n, mcu_wr_n, mcu_a0;
wire [7:0]  mcu_host_din;  // CPU dout, latched by iface, presented to i8041

mcu_tape_iface mcu_tape_iface_inst (
	.clk_sys              (clk_sys),
	.ce_hclk              (ce_hclk),
	.ce_hclk1             (ce_hclk1),
	.ce_tape              (ce_tape),
	.reset                (reset),
	.mcu_p1_in            (mcu_p1_in),
	.mcu_p1_out           (mcu_p1_out),
	.mcu_p2_in            (mcu_p2_in),
	.mcu_p2_out           (mcu_p2_out),
	.mcu_t0               (mcu_t0),
	.mcu_t1               (mcu_t1),
	.mcu_cs_n             (mcu_cs_n),
	.mcu_rd_n             (mcu_rd_n),
	.mcu_wr_n             (mcu_wr_n),
	.mcu_a0               (mcu_a0),
	.mcu_dout             (mcu_host_din),
	.tape_motor_on        (tape_motor_on),
	.tape_direction       (tape_direction),
	.tape_speed_select    (tape_speed_select),
	.tape_data            (tape_data),
	.tape_clock           (tape_clock),
	.tape_bot             (tape_bot),
	.tape_eot             (tape_eot),
	.cpu_e5_re            (cpu_re_e5xx),
	.cpu_e5_we            (cpu_we_e5xx),
	.cpu_addr_lo          (cpu_addr[7:0]),
	.cpu_dout             (cpu_dout),
	.cpu_din              (e5xx_dongle),
	.mcu_host_dout        (mcu_host_dout),
	.mcu_host_dout_oe     (mcu_host_dout_oe),
	.dongle_addr_lo       (dongle_addr_lo),
	.dongle_re            (dongle_re),
	.dongle_we            (dongle_we),
	.dongle_dout          (dongle_dout),
	.dongle_din_low4      (dongle_din_low4)
);

// E5xx dongle response is automatically composed in mcu_tape_iface
// as {mcu_p2_out[7:4], dongle_din_low4}

// =========================================================================
// CASSETTE BRAM (64 KB) + cassette_loader (task 25 / phase 16)
// =========================================================================
// 64 KB covers all known DECO cassettes (largest is 0x10000 = 64 KB; most
// are 0x8000 = 32 KB). cassette_loader writes from hps_io on port A;
// tape_streamer reads on port B during playback.
wire [15:0] cass_load_addr;
wire [7:0]  cass_load_dout;
wire        cass_load_we;
wire [17:0] tape_image_size;

// 2026-05-18 — CRC16 table wires (computed by cassette_loader, read by tape_streamer)
wire [7:0]  crc_table_addr_w;
wire [15:0] crc_table_data_w;
wire        crc_table_we_w;

cassette_loader cassette_loader_inst (
    .clk_sys          (clk_sys),
    .ioctl_download   (ioctl_download),
    .ioctl_wr         (ioctl_wr),
    .ioctl_addr       (ioctl_addr),
    .ioctl_dout       (ioctl_dout),
    .bram_addr        (cass_load_addr),
    .bram_dout        (cass_load_dout),
    .bram_we          (cass_load_we),
    .crc_table_addr   (crc_table_addr_w),
    .crc_table_data   (crc_table_data_w),
    .crc_table_we     (crc_table_we_w),
    .image_size_bytes (tape_image_size)
);

// CRC16 lookup table — 256 blocks × 16 bits.
// Port A: written by cassette_loader as bytes stream in.
// Port B: read by tape_streamer when streaming CRC bytes.
wire [7:0]  crc_table_q_addr;
wire [15:0] crc_table_q;
dpram #(.address_width(8), .data_width(16)) crc16_table_bram (
    .clock_a  (clk_sys),
    .enable_a (1'b1),
    .wren_a   (crc_table_we_w),
    .address_a(crc_table_addr_w),
    .data_a   (crc_table_data_w),
    .q_a      (),
    .clock_b  (clk_sys),
    .enable_b (1'b1),
    .wren_b   (1'b0),
    .address_b(crc_table_q_addr),
    .data_b   (16'h0000),
    .q_b      (crc_table_q)
);

// Tape Streamer (task 16)
wire [17:0] tape_image_addr;
wire [7:0]  tape_image_q;

dpram #(.address_width(16), .data_width(8)) cassette_bram (
    .clock_a   (clk_sys),
    .enable_a  (1'b1),
    .address_a (cass_load_addr),
    .data_a    (cass_load_dout),
    .wren_a    (cass_load_we),
    .q_a       (),

    .clock_b   (clk_sys),
    .enable_b  (1'b1),
    .address_b (tape_image_addr[15:0]),
    .data_b    (8'h00),
    .wren_b    (1'b0),
    .q_b       (tape_image_q)
);

tape_streamer tape_streamer_inst (
	.clk_sys           (clk_sys),
	.ce_tape           (ce_tape),
	.reset             (reset),
	.image_addr        (tape_image_addr),
	.image_q           (tape_image_q),
	.image_size_bytes  (tape_image_size),
	.motor_on          (tape_motor_on),
	.direction         (tape_direction),
	.speed_select      (tape_speed_select),
	.crc_addr          (crc_table_q_addr),
	.crc_q             (crc_table_q),
	.tape_data         (tape_data),
	.tape_clock        (tape_clock),
	.tape_bot          (tape_bot),
	.tape_eot          (tape_eot)
);

// =========================================================================
// DONGLES (task 18 — mux; tasks 19-22 — type implementations)
// =========================================================================
wire [11:0] dprom_addr;       // 12-bit (4 KB) — Type 3 needs full width
wire [7:0]  dprom_q;

dongle_mux dongle_mux_inst (
	.clk_sys           (clk_sys),
	.ce_hclk4          (ce_hclk4),
	.reset             (reset),
	.dongle_type       (dongle_type),
	.game_id           (game_id),
	.swap_mode         (swap_mode),
	.cpu_re            (dongle_re),
	.cpu_we            (dongle_we),
	.cpu_addr_lo       (dongle_addr_lo),
	.cpu_dout          (dongle_dout),
	.cpu_din_full      (dongle_din_full),       // 2026-05-18: 8-bit per MAME
	.dprom_addr        (dprom_addr),
	.dprom_q           (dprom_q),
	// 2026-05-18 — dongle reads MCU host-bus registers per MAME
	// `upi41_master_r(0)/(1)`. mcu_dbb_sts faked as OBF=mcu_host_dout_oe.
	.mcu_dbb_dout      (mcu_host_dout),
	// DBBSTS exposure 2026-05-30: real STATUS reg (sts/f1/f0/IBF/OBF) from the i8041 core —
	// was faked as {6'b0,IBF=0,OBF=host_dout_oe}. Needed for the BIOS<->MCU tape handshake.
	.mcu_dbb_sts       (mcu_host_sts),
	.mcu_status_d2     (mcu_p2_out[2]),
	.mcu_status_d0     (mcu_p2_out[0])
);

// Tie legacy `dongle_din_low4` to the low nibble of the 8-bit output
// (mcu_tape_iface still uses dongle_din_low4 for its cpu_din formula).
assign dongle_din_low4 = dongle_din_full[3:0];

// DONGLE BYPASS FIX 2026-05-30: the $E5xx read must go through the dongle on the DATA path.
// MAME decocass_e5xx_r: (offset & E5XX_MASK)==2 -> composite STATUS byte; else -> m_dongle_r(offset).
// e5xx_dongle (from mcu_tape_iface) already returns the correct STATUS byte for cpu_addr[1]==1, so
// keep it there; route cpu_addr[1]==0 (DATA) through dongle_mux's dongle_din_full (nodong/type1/
// type3 each handle their A0 split internally). Was: decocass.v fed raw e5xx_dongle, dongle ignored.
assign e5xx_to_cpu = cpu_addr[1] ? e5xx_dongle : dongle_din_full;

// Dongle PROM (4 KB, shared across types 2-5; Type 3 needs full 4 KB).
// During load: rom_loader drives dongleprom_addr; during run: dongle_mux drives dprom_addr.
wire [11:0] dongleprom_addr_eff = dongleprom_we ? dongleprom_addr : dprom_addr;

spram #(.address_width(12), .data_width(8)) dongle_prom (
	.clock     (clk_sys),
	.enable    (1'b1),
	.address   (dongleprom_addr_eff),
	.data      (dongleprom_dout),
	.wren      (dongleprom_we),
	.q         (dprom_q)
);

// =========================================================================
// INPUT MUX (task 23)
// =========================================================================
wire [7:0]  input_q;

// Prepare input signals from joysticks/buttons (inverted per MAME)
wire [7:0] in0, in1, in2;
assign in0 = {2'b11, ~joystick_0[5:0]};         // P1: bits[5:0]=R/L/U/D/B1/B2
assign in1 = {2'b11, ~joystick_1[5:0]};         // P2: bits[5:0]=R/L/U/D/B1/B2
assign in2 = {~joystick_0[15], 1'b1, ~joystick_0[13], 1'b1, ~joystick_0[14], ~joystick_1[14], ~joystick_0[12], 1'b1};  // Coins, starts

inputs inputs_inst (
	.clk_sys          (clk_sys),
	.ce_hclk1         (ce_hclk1),
	.reset            (reset),
	.cpu_addr_lo      (cpu_addr[7:0]),
	.cpu_we_e6xx      (cpu_we_e6xx),
	.cpu_rw_n         (cpu_rw_n),
	.in0              (in0),
	.in1              (in1),
	.in2              (in2),
	.dsw1             (sw[2]),
	.dsw2             (sw[3]),
	.vblank           (video_vblank),
	.mcu_p2_low4      (mcu_p2_out[3:0]),
	.input_q          (input_q)
);

// =========================================================================
// WATCHDOG (task 23)
// =========================================================================
watchdog watchdog_inst (
	.clk_sys          (clk_sys),
	.ce_hclk1         (ce_hclk1),
	.reset            (reset),
	.vblank_pulse     (~video_vblank),
	.wd_count_w       (cpu_we_e3xx && cpu_addr[0] == 1'b0),
	.wd_flip_w        (cpu_we_e3xx && cpu_addr[0] == 1'b1),
	.cpu_dout         (cpu_dout),
	.dsw1             (sw[2]),
	.wd_reset         (),
	.flip_screen      ()
);

// =========================================================================
// AUDIO CPU (task 12)
// =========================================================================
wire [7:0]  audio_cpu_addr, audio_cpu_dout, audio_cpu_din;
wire        audio_cpu_rw_n;
wire        ay1_data_we, ay1_addr_we, ay2_data_we, ay2_addr_we;
wire [7:0]  ay_data_out;

// Sound latch ↔ audio CPU glue wires
wire        audio_to_main_we;
wire        audio_from_main_re;
wire [7:0]  audio_to_main_data;
wire [7:0]  main_to_audio_data;
wire        audio_irq;
reg         audio_nmi_enable_reg;   // $E416 bit 0 — main CPU's master enable for audio NMI

audio_cpu audio_cpu_inst (
	.clk_sys      (clk_sys),
	.ce_audio     (ce_audio),
	.reset        (reset),
	.ce_pix       (ce_pix),
	.audio_irq_set(audio_irq),
	.hcounter_eq_0(hcnt == 9'h000),
	.vcounter     (vcnt),
	.rom_we       (abios_we_rom),
	.rom_addr_w   (abios_addr_rom),
	.rom_data_w   (abios_dout_rom),
	.ay1_data_we  (ay1_data_we),
	.ay1_addr_we  (ay1_addr_we),
	.ay2_data_we  (ay2_data_we),
	.ay2_addr_we  (ay2_addr_we),
	.ay_data_out  (ay_data_out),
	.sound_to_main_we(audio_to_main_we),
	.sound_from_main_re(audio_from_main_re),
	.sound_to_main(audio_to_main_data),
	.sound_from_main(main_to_audio_data),
	.audio_nmi_master_enable(audio_nmi_enable_reg)
);

// =========================================================================
// AUDIO NMI ENABLE GATE (from main CPU $E416 write)
// =========================================================================
// Per MAME decocass.cpp, audio NMI enable is set by main CPU writes to $E416.
// This implements a simple register that latches the NMI enable gate per bit 0 of the write.
wire cpu_we_e416 = (cpu_addr == 16'hE416 && !cpu_rw_n && ce_hclk4);

always @(posedge clk_sys) begin
	if (reset)
		audio_nmi_enable_reg <= 1'b0;
	else if (cpu_we_e416)
		audio_nmi_enable_reg <= cpu_dout[0];
end

// =========================================================================
// SOUND LATCHES (task 14) — $E414, $E700, $E701
// =========================================================================
wire [7:0]  sound_data, sound_ack;

sound_latches sound_latches_inst (
	.clk_sys       (clk_sys),
	.reset         (reset),
	.ce_main       (ce_hclk1),
	.main_we_e414  (cpu_we_e414),
	.main_re_e700  (cpu_re_e700),
	.main_re_e701  (cpu_re_e701),
	.main_dout     (cpu_dout),
	.main_din_e700 (sound_data),
	.main_din_e701 (sound_ack),
	.ce_audio      (ce_audio),
	.audio_we_c000 (audio_to_main_we),
	.audio_re_a000 (audio_from_main_re),
	.audio_dout    (audio_to_main_data),
	.audio_din_a000(main_to_audio_data),
	.audio_irq     (audio_irq)
);

// =========================================================================
// AY-3-8910 PAIR (task 13)
// =========================================================================
wire signed [15:0] ay_left, ay_right;

ay8910_pair ay8910_pair_inst (
	.clk_sys      (clk_sys),
	.ce_hclk2     (ce_hclk2),
	.ce_audio     (ce_audio),
	.reset        (reset),
	.ay1_data_we  (ay1_data_we),
	.ay1_addr_we  (ay1_addr_we),
	.ay2_data_we  (ay2_data_we),
	.ay2_addr_we  (ay2_addr_we),
	.audio_dout   (ay_data_out),
	.sound_out    ({ay_right, ay_left})
);

// =========================================================================
// VIDEO SUBSYSTEM (tasks 07-11)
// =========================================================================
wire [4:0]  fg_pen, bg_pen, spr_pen, mis_pen;
wire        fg_opaque, bg_opaque, spr_opaque, mis_opaque;

// Video timing
video_timing video_timing_inst (
	.clk_sys      (clk_sys),
	.ce_pix       (ce_pix),
	.reset        (reset),
	.hsync        (video_hsync),
	.vsync        (video_vsync),
	.hblank       (video_hblank),
	.vblank       (video_vblank),
	.hcnt         (hcnt),
	.vcnt         (vcnt),
	.vsync_pulse  ()
);

// FG tilemap (task 08)
video_fg video_fg_inst (
	.clk_sys           (clk_sys),
	.ce_pix            (ce_pix),
	.hcnt              (hcnt),
	.vcnt              (vcnt),
	.cpu_we_fg         (cpu_we_fgvram),
	.cpu_we_col        (cpu_we_colram),
	.cpu_we_char_p0    (charram_we_p0),
	.cpu_we_char_p1    (charram_we_p1),
	.cpu_we_char_p2    (charram_we_p2),
	.cpu_addr          (cpu_addr[12:0]),       // 13-bit (covers 8 KB plane + 1 KB fg/col)
	.cpu_dout          (cpu_dout),
	.color_center_bot  (color_center_bot_reg), // $E410 — bit 0 → FG color
	.fg_pen            (fg_pen),
	.fg_opaque         (fg_opaque)
);

// BG tilemaps (task 09)
video_bg video_bg_inst (
	.clk_sys           (clk_sys),
	.ce_pix            (ce_pix),
	.hcnt              (hcnt),
	.vcnt              (vcnt),
	.back_h_shift      (back_h_shift_reg),
	.back_vl_shift     (back_vl_shift_reg),
	.back_vr_shift     (back_vr_shift_reg),
	.mode_set          (mode_set_reg),
	.color_center_bot  (color_center_bot_reg),
	.cpu_we_tile       (cpu_we_tilram),
	.cpu_addr_tile     (cpu_addr[10:0]),
	.cpu_dout          (cpu_dout),
	.bg_pen            (bg_pen),
	.bg_opaque         (bg_opaque)
);

// Sprites (task 10)
video_sprites video_sprites_inst (
	.clk_sys           (clk_sys),
	.ce_pix            (ce_pix),
	.hcnt              (hcnt),
	.vcnt              (vcnt),
	.color_center_bot  (color_center_bot_reg),
	.cpu_we_spr        (cpu_we_fgvram),
	.cpu_spr_addr      (cpu_addr[9:0]),
	.cpu_spr_dout      (cpu_dout),
	.spr_pen           (spr_pen),
	.spr_priority      (spr_opaque)
);

// Missiles (task 10)
video_missiles video_missiles_inst (
	.clk_sys           (clk_sys),
	.ce_pix            (ce_pix),
	.hcnt              (hcnt),
	.vcnt              (vcnt),
	.color_missiles    (8'h00),
	.cpu_we_mis        (cpu_we_colram),
	.cpu_mis_addr      (cpu_addr[9:0]),
	.cpu_mis_dout      (cpu_dout),
	.mis_pen           (mis_pen),
	.mis_priority      (mis_opaque)
);

// Internal core RGB (8-bit each) — palette upper nibble + replicated lower
wire [3:0] core_r_hi, core_g_hi, core_b_hi;
wire [5:0] mixer_pen;
wire       mixer_modulate;
// DIAG-REVERT-2026-05-29: DECOCassette video-state overlay   >>> DIAGNOSTIC >>>
// Mirrors the Kyugo swatch overlay (kyugo_video_audit_2026-05-28). Predecessor's
// compile-6 showed mixer_pen stuck at 8 (BG_FILL) everywhere -> screen = palette[8].
// Two unknowns this splits in ONE compile: (1) is the palette RAM actually populated
// with real colour, or empty/black? (2) does any layer EVER become opaque (renderer
// produces a pixel)? Bands at top of the (pre-rotation) raster:
//
//   vcnt 16..31 : ROW 1 — 8 PROOF-OF-LIFE cells, 32px each. DISTINCT colour if the
//                 sticky flag is TRUE, else BLACK. These are the "did the CPU get PAST
//                 the MCU handshake" milestones — once the handshake is fixed they flip on:
//     0 GREEN   cpu_alive       — deco222 address bus is changing (executing)
//     1 CYAN    cpu_sync_ever   — CPU fetched at least one opcode (cpu_sync pulsed)
//     2 BLUE    palram_wr_ever  — BIOS has written palette RAM ($E000-$E0FF)
//     3 RED     charram_wr_ever — CPU wrote FG char planes (glyph bitmap data)
//     4 YELLOW  fgvram_wr_ever  — CPU wrote the FG tilemap (which glyph where)
//     5 MAGENTA mixer_nonfill   — mixer_pen was EVER != 8 (a layer won priority)
//     6 ORANGE  tape_motor_ever — cassette transport ran (the "USER LED" sign of life)
//     7 WHITE   calibration     — ALWAYS on (proves overlay renders + rbf is fresh +
//                                 pause->arcade_video->scaler output path is alive)
//   vcnt 32..47 : ROW 2 — 8 SOUND-HANDSHAKE cells (main<->audio 6502; the suspected stall;
//                 see the row-2 colour legend at the cell2_* block below). DECO twin of
//                 Kyugo's row-2 coprocessor probe.
//   vcnt 48..79 : CPU BUS BAR — RGB straight from cpu_addr/cpu_dout. Moving stipple =
//                 CPU executing across addresses; a frozen solid block = stuck/halted.
//   vcnt 80..207: PALETTE SWATCH — 8x4 grid, palette read index forced to the cell
//                 index 0..31, shown through the NORMAL palette path. Real colours =
//                 palette RAM populated; all-black = palette empty (the Kyugo bug
//                 class). Cell 8 (row 1, col 0) is pen 8 = BG_FILL = the whole-screen
//                 colour when the mixer is stuck — if cell 8 is black the bg fill
//                 itself is unwritten.
//   vcnt 208..247: untouched normal game render.
//
// READING IT: cell7 white but cell0 black -> CPU halted (root). cell0 green but cell2
//   black -> BIOS never wrote palette -> swatch black -> palette empty. cell2 green
//   but swatch still all-black -> palette write/decode path broken (look at the XOR /
//   invert in video_palette.v). swatch colourful but cell5 black -> palette fine, no
//   layer ever opaque -> renderer never emits a pixel (FG transparent everywhere:
//   prefetch / opaque-flag bug). swatch colourful + cell5 green + game band still
//   black -> mixing/priority bug downstream.
//
// REVERT: delete this whole block, restore .pen(mixer_pen) on video_palette_inst, and
// uncomment the 3 original core_r/g/b assigns just below.
//========================================================================
reg cpu_sync_ever, palram_wr_ever, charram_wr_ever, fgvram_wr_ever;
reg mixer_nonfill_ever, tape_motor_ever;
reg [15:0] diag_a_prev;
reg [19:0] diag_alive_cnt;
// Row-2 (main<->audio-CPU SOUND handshake) sticky probes — the suspected stall site.
reg e414_we_ever, e701_rd_ever, e700_rd_ever, a000_re_ever, c000_we_ever, airq_ever;
reg [7:0]  audio_a_prev;
reg [19:0] audio_alive_cnt;
// TAPE-DECK chain-of-custody (row 2 repurposed 2026-05-30): traces the load handshake.
reg e5wr_ever, ibf_ever, rclk_ever, rdata_ever, obf_ever, req_ever, e5rd_ever;
reg mcu_wr_seen_ever;  // DIAG-REVERT-2026-05-30: does the host WR strobe physically reach the MCU pin? (was cell7 - CONFIRMED white)
reg sts_any_ever;      // DIAG-REVERT-2026-05-30: is the MCU status reg EVER non-zero? (was cell7) CONFIRMED BLACK
reg cs_low_ever;       // DIAG-REVERT-2026-05-30: did mcu_cs_n ever assert (go low)? (cell6)
reg wrs_ever;          // DIAG-REVERT-2026-05-30: did write_s (cs_n & wr_n BOTH low) ever assert at the MCU pin? (cell7)
reg mcu_exec_ever, mcu_sync_prev;  // DIAG-REVERT-2026-05-30: did mcu_sync_o ever TOGGLE (MCU executing)? (cell6)
reg ibf_cleared_ever;  // DIAG-REVERT-2026-05-30: did IBF go LOW after being high (MCU consumed the cmd via IN A,DBB)? (cell7)
reg [7:0] mcu_p1_prev, mcu_p2_prev; reg port_post_cmd_ever;  // DIAG-REVERT-2026-05-30: did MCU drive any p1/p2 OUT bit AFTER consuming a cmd? (cell7)
always @(posedge clk_sys) begin
    if (reset) begin
        cpu_sync_ever <= 1'b0; palram_wr_ever <= 1'b0; charram_wr_ever <= 1'b0;
        fgvram_wr_ever <= 1'b0; mixer_nonfill_ever <= 1'b0; tape_motor_ever <= 1'b0;
        diag_a_prev <= 16'd0; diag_alive_cnt <= 20'd0;
        e414_we_ever <= 1'b0; e701_rd_ever <= 1'b0; e700_rd_ever <= 1'b0;
        a000_re_ever <= 1'b0; c000_we_ever <= 1'b0; airq_ever <= 1'b0;
        audio_a_prev <= 8'd0; audio_alive_cnt <= 20'd0;
        e5wr_ever<=1'b0; ibf_ever<=1'b0; rclk_ever<=1'b0; rdata_ever<=1'b0; obf_ever<=1'b0; req_ever<=1'b0; e5rd_ever<=1'b0;
        mcu_wr_seen_ever <= 1'b0;  // DIAG-REVERT-2026-05-30
        sts_any_ever <= 1'b0;      // DIAG-REVERT-2026-05-30
        cs_low_ever <= 1'b0;       // DIAG-REVERT-2026-05-30
        wrs_ever <= 1'b0;          // DIAG-REVERT-2026-05-30
        mcu_exec_ever <= 1'b0; mcu_sync_prev <= 1'b0;  // DIAG-REVERT-2026-05-30
        ibf_cleared_ever <= 1'b0;  // DIAG-REVERT-2026-05-30
        mcu_p1_prev <= 8'd0; mcu_p2_prev <= 8'd0; port_post_cmd_ever <= 1'b0;  // DIAG-REVERT-2026-05-30
    end else begin
        if (cpu_sync)            cpu_sync_ever      <= 1'b1;
        if (cpu_we_palram)       palram_wr_ever     <= 1'b1;
        if (charram_we_any)      charram_wr_ever    <= 1'b1;
        if (cpu_we_fgvram)       fgvram_wr_ever     <= 1'b1;
        if (mixer_pen != 6'd8)   mixer_nonfill_ever <= 1'b1;
        if (tape_motor_on)       tape_motor_ever    <= 1'b1;
        diag_a_prev <= cpu_addr;
        if (cpu_addr != diag_a_prev)      diag_alive_cnt <= 20'hFFFFF;
        else if (diag_alive_cnt != 20'd0) diag_alive_cnt <= diag_alive_cnt - 20'd1;
        // Row 2 — main<->audio-CPU sound handshake ($E414 / $E700 / $E701 / $A000 / $C000)
        if (cpu_we_e414)        e414_we_ever <= 1'b1;  // main sent a sound command
        if (cpu_re_e701)        e701_rd_ever <= 1'b1;  // main polled the sound-ack (the spin)
        if (cpu_re_e700)        e700_rd_ever <= 1'b1;  // main read sound data
        if (audio_from_main_re) a000_re_ever <= 1'b1;  // audio CPU consumed the cmd ($A000 read)
        if (audio_to_main_we)   c000_we_ever <= 1'b1;  // audio CPU wrote a response ($C000)
        if (audio_irq)          airq_ever    <= 1'b1;  // sound IRQ to the audio CPU ever asserted
        audio_a_prev <= audio_cpu_addr;
        if (audio_cpu_addr != audio_a_prev) audio_alive_cnt <= 20'hFFFFF;
        else if (audio_alive_cnt != 20'd0)  audio_alive_cnt <= audio_alive_cnt - 20'd1;
        // TAPE-DECK chain-of-custody latches (row 2)
        if (cpu_we_e5xx)     e5wr_ever  <= 1'b1;   // BIOS wrote a command to the MCU
        if (mcu_host_sts[1]) ibf_ever   <= 1'b1;   // MCU input-buffer-full (got the command)
        if (tape_clock)      rclk_ever  <= 1'b1;   // deck produced a read clock
        if (tape_data)       rdata_ever <= 1'b1;   // deck produced read data
        if (mcu_host_sts[0]) obf_ever   <= 1'b1;   // MCU output-buffer-full (assembled a byte)
        if (~mcu_p1_out[7])  req_ever   <= 1'b1;   // MCU asserted REQ/ (signaled the BIOS)
        if (cpu_re_e5xx)     e5rd_ever  <= 1'b1;   // BIOS read $E5xx (consumed status/data)
        if (~mcu_wr_n)       mcu_wr_seen_ever <= 1'b1;  // DIAG-REVERT-2026-05-30: host WR strobe asserted at the MCU pin
        if (|mcu_host_sts)   sts_any_ever <= 1'b1;       // DIAG-REVERT-2026-05-30: any MCU status bit ever set (core bus-regs alive?)
        if (~mcu_cs_n)             cs_low_ever <= 1'b1;  // DIAG-REVERT-2026-05-30: cs_n asserted at the MCU pin
        if (~mcu_cs_n & ~mcu_wr_n) wrs_ever    <= 1'b1;  // DIAG-REVERT-2026-05-30: write_s (cs_n & wr_n both low) at the MCU pin
        mcu_sync_prev <= mcu_sync_o;                                       // DIAG-REVERT-2026-05-30
        if (mcu_sync_o != mcu_sync_prev) mcu_exec_ever <= 1'b1;            // DIAG-REVERT-2026-05-30: sync_o toggled => MCU executing
        if (ibf_ever & ~mcu_host_sts[1]) ibf_cleared_ever <= 1'b1;         // DIAG-REVERT-2026-05-30: IBF went low after high => MCU read DBBIN
        mcu_p1_prev <= mcu_p1_out; mcu_p2_prev <= mcu_p2_out;              // DIAG-REVERT-2026-05-30
        if (ibf_cleared_ever & ((mcu_p1_out != mcu_p1_prev) | (mcu_p2_out != mcu_p2_prev))) port_post_cmd_ever <= 1'b1;  // DIAG-REVERT-2026-05-30: MCU drove a port out after consuming a cmd
    end
end
wire cpu_alive = (diag_alive_cnt != 20'd0);
wire audio_alive = (audio_alive_cnt != 20'd0);

// Band detection (pre-rotation raster; DECO visible = hcnt 0..255, vcnt 8..247)
wire diag_status  = (vcnt >= 9'd16) & (vcnt < 9'd32)  & (hcnt < 9'd256);  // row 1 (proof-of-life)
wire diag_status2 = (vcnt >= 9'd32) & (vcnt < 9'd48)  & (hcnt < 9'd256);  // row 2 (sound handshake)
wire diag_busbar  = (vcnt >= 9'd48) & (vcnt < 9'd80)  & (hcnt < 9'd256);
wire diag_swatch = (vcnt >= 9'd80) & (vcnt < 9'd208) & (hcnt < 9'd256);

wire [2:0] diag_cell = hcnt[7:5];                 // 0..7, 32px cells
wire [2:0] sw_col    = hcnt[7:5];                 // 0..7
wire [1:0] sw_row    = (vcnt - 9'd80) >> 5;       // 0..3, 32 lines per row
wire [4:0] diag_swatch_index = {sw_row, sw_col};  // 0..31

// Status cells: distinct saturated colours, BLACK when the flag is false.
reg [7:0] cell_r, cell_g, cell_b;
always @(*) begin
    cell_r = 8'd0; cell_g = 8'd0; cell_b = 8'd0;
    case (diag_cell)
        3'd0: if (cpu_alive)          cell_g = 8'hFF;                           // GREEN
        3'd1: if (cpu_sync_ever)      begin cell_g = 8'hFF; cell_b = 8'hFF; end // CYAN
        3'd2: if (palram_wr_ever)     cell_b = 8'hFF;                           // BLUE
        3'd3: if (charram_wr_ever)    cell_r = 8'hFF;                           // RED
        3'd4: if (fgvram_wr_ever)     begin cell_r = 8'hFF; cell_g = 8'hFF; end // YELLOW
        3'd5: if (mixer_nonfill_ever) begin cell_r = 8'hFF; cell_b = 8'hFF; end // MAGENTA
        // DIAG-REVERT-2026-05-30: cell6 was tape_motor_ever (orig below); now cs_low_ever.
        // 3'd6: if (tape_motor_ever)    begin cell_r = 8'hFF; cell_g = 8'h80; end // ORANGE (orig)
        3'd6: if (mcu_exec_ever)      begin cell_r = 8'hFF; cell_g = 8'h80; end // ORANGE = MCU sync_o TOGGLED (core is EXECUTING)
        // DIAG-REVERT-2026-05-30: cell7 was a static WHITE calib marker; repurposed to mcu_wr_seen_ever.
        //   WHITE = host WR strobe reaches the MCU pin (bug is INSIDE the core's write_pulse sampling)
        //   BLACK = iface never pulses mcu_wr_n      (bug is in mcu_tape_iface strobe gen, lines 207-244)
        // 3'd7:                         begin cell_r = 8'hFF; cell_g = 8'hFF; cell_b = 8'hFF; end // WHITE (orig static)
        3'd7: if (port_post_cmd_ever) begin cell_r = 8'hFF; cell_g = 8'hFF; cell_b = 8'hFF; end // WHITE = MCU drove a p1/p2 OUTPUT bit AFTER consuming a cmd
    endcase
end

// Row 2 — main<->audio-CPU SOUND handshake probe (decocass.v:331 warns the main "may
// spin on sound handshake" if the ack flag never clears). Same colour key:
//   0 GREEN   audio_alive  — audio 6502 address bus changing (it's actually running)
//   1 CYAN    e414_we_ever — main wrote $E414 (sent a sound cmd -> sets ack D7, IRQs audio)
//   2 BLUE    e701_rd_ever — main read $E701 (polling the sound-ack — THE spin)
//   3 RED     e700_rd_ever — main read $E700 (sound response data)
//   4 YELLOW  a000_re_ever — audio read $A000 (CONSUMED the cmd -> should clear ack D7)
//   5 MAGENTA c000_we_ever — audio wrote $C000 (sent a response -> sets ack D6)
//   6 ORANGE  airq_ever    — the sound IRQ to the audio CPU ever asserted
//   7 WHITE   calibration
// READ: cell0 black -> audio CPU dead (root). cell1 black -> main never sent a sound cmd
//   => the spin is NOT the sound handshake (look at $E300/$E6xx/RAM). cell1+cell6 green
//   but cell4 BLACK -> main sent cmd + IRQ fired, audio NEVER serviced it ($A000) -> ack
//   D7 never clears -> main spins (THE bug; fix audio IRQ enable/handler). cell4 green
//   but row-1 still black -> audio consumes but our $E701 ack-bit polarity is wrong.
reg [7:0] cell2_r, cell2_g, cell2_b;
always @(*) begin
    cell2_r = 8'd0; cell2_g = 8'd0; cell2_b = 8'd0;
    case (diag_cell)
        // TAPE-DECK chain-of-custody (position = load-handshake order; read by POSITION, see HANDOFF)
        3'd0: if (e5wr_ever)       begin cell2_g = 8'hFF; cell2_b = 8'hFF; end // 0 E5WR  BIOS wrote cmd
        3'd1: if (ibf_ever)        cell2_b = 8'hFF;                            // 1 IBF   MCU got cmd
        3'd2: if (tape_motor_ever) begin cell2_r = 8'hFF; cell2_g = 8'h80; end // 2 MOTOR spun tape
        3'd3: if (rclk_ever)       cell2_g = 8'hFF;                            // 3 RCLK  deck clock
        3'd4: if (rdata_ever)      begin cell2_r = 8'hFF; cell2_g = 8'hFF; end // 4 RDATA deck data
        3'd5: if (obf_ever)        begin cell2_r = 8'hFF; cell2_b = 8'hFF; end // 5 OBF   MCU has byte
        3'd6: if (req_ever)        cell2_r = 8'hFF;                            // 6 REQ   MCU signaled BIOS
        3'd7: if (e5rd_ever)       begin cell2_r = 8'hFF; cell2_g = 8'hFF; cell2_b = 8'hFF; end // 7 E5RD BIOS read
    endcase
end

// DIAG-2026-05-30 (PC-LATCH PROBE): capture the address the early spin loop POLLS.
// In a stuck "LDA $XXXX / Bxx" loop, latch cpu_addr on any non-ROM DATA READ ($XXXX < $F000)
// → last_rd settles to the polled peripheral/RAM address. Then disasm $Fxxx around it.
// Shown in the BUS BAR band (vcnt 48..79, repurposed — it already proved "tight loop"):
// 16 bit-cells, MSB at the LEFT. Cells 0..7 = HIGH byte (CYAN), cells 8..15 = LOW byte (YELLOW),
// lit = 1. Read as two hex bytes: e.g. cyan 1110_0101 + yellow 0000_0010 = $E502.
reg [15:0] last_rd;
always @(posedge clk_sys) begin
    if (reset)                                               last_rd <= 16'd0;
    else if (ce_hclk4 && cpu_rw_n && (cpu_addr < 16'hF000))  last_rd <= cpu_addr;
end
wire [3:0] lrd_cell = hcnt[7:4];                  // 0..15 across the 256px band
wire       lrd_bit  = last_rd[4'd15 - lrd_cell];  // MSB (bit15) at the left
reg [7:0] lrd_r, lrd_g, lrd_b;
// DIM-GRID 2026-05-30: every one of the 16 cells is shown DIM (you can't count black cells),
// the actual bits are FULL bright. Dim shade alternates per nibble (cells 0-3 / 4-7 / 8-11 /
// 12-15) so you can read it as 4 hex digits. Left 8 = CYAN high byte, right 8 = YELLOW low byte.
wire [7:0] lrd_lvl = lrd_bit ? 8'hFF : (lrd_cell[2] ? 8'h30 : 8'h10);  // lit=full, else dim (nibble-alt)
always @(*) begin
    lrd_r = 8'd0; lrd_g = 8'd0; lrd_b = 8'd0;
    if (lrd_cell < 4'd8) begin lrd_g = lrd_lvl; lrd_b = lrd_lvl; end // CYAN  = high byte [15:8]
    else                 begin lrd_r = lrd_lvl; lrd_g = lrd_lvl; end // YELLOW = low byte  [7:0]
end

// Direct-colour bands bypass the palette entirely (status cells + CPU bus bar),
// which doubles as the Kyugo "force-colour" output-path test: if even the WHITE
// calibration cell is black, the bug is the pause->arcade_video->scaler path, not
// the palette or renderer.
wire       diag_direct = diag_status | diag_status2 | diag_busbar;
// DIAG-2026-05-30: bus-bar band (else) now shows the LATCHED POLLED ADDRESS (last_rd) as
// 16 bit-cells (was raw cpu_addr/cpu_dout). Restore = put cpu_addr[15:8]/[7:0]/cpu_dout back.
wire [7:0] diag_r8 = diag_status ? cell_r : diag_status2 ? cell2_r : lrd_r;
wire [7:0] diag_g8 = diag_status ? cell_g : diag_status2 ? cell2_g : lrd_g;
wire [7:0] diag_b8 = diag_status ? cell_b : diag_status2 ? cell2_b : lrd_b;

// Palette read index: forced to the swatch index inside the swatch band.
wire [5:0] diag_pen = diag_swatch ? {1'b0, diag_swatch_index} : mixer_pen;

// DIAG-REVERT-2026-05-29: original 3 core RGB assigns below, uncomment to restore
// wire [7:0] core_r = {core_r_hi, core_r_hi};
// wire [7:0] core_g = {core_g_hi, core_g_hi};
// wire [7:0] core_b = {core_b_hi, core_b_hi};
// DIAG OFF 2026-05-30 — overlay disabled to view the clean boot logo (the decrypt fix worked).
// Re-arm: restore `diag_direct ? diag_r8/g8/b8 :` and `.pen(diag_pen)` below.
// RE-ARMED 2026-05-30 for the TAPE-DECK chain overlay (row 2) + the bus-bar last_rd probe.
// Swatch (.pen) stays OFF. Disable: set these back to just {core_*_hi, core_*_hi}.
wire [7:0] core_r = diag_direct ? diag_r8 : {core_r_hi, core_r_hi};
wire [7:0] core_g = diag_direct ? diag_g8 : {core_g_hi, core_g_hi};
wire [7:0] core_b = diag_direct ? diag_b8 : {core_b_hi, core_b_hi};
// DIAG-REVERT-2026-05-29: DECOCassette video-state overlay   <<< END DIAGNOSTIC <<<
//========================================================================

// Palette lookup (task 11)
//
// 2026-05-16: WHITE-SCREEN ROOT CAUSE.
// Per MAME decocass_v.cpp:323-333 (`decocass_paletteram_w`):
//     offset = (offset & 31) ^ 16;
//     m_palette->set_indirect_color(offset, ...);
// The hardware XORs bit 4 (and mod-32s) the CPU's write offset before
// committing it to the indirect-color table that drives video output.
// Without this XOR, BIOS writes meant for pen-N color land at palette
// index N — including the critical pen-8 color (`BG_FILL` in
// video_mixer.v), which BIOS writes to $E000+24 expecting it to map
// to palette[8] via the XOR. Without the XOR, palette[8] stays at 0,
// `clut_index = palram_dout[4:0] = 0`, CLUT[0] = 12'hFFF = PURE WHITE.
// Symptom: hours of "white screen, can't get past it." The audio-hijack
// rounds proved BIOS was writing real non-zero data; the writes just
// went to the wrong addresses. Now applying the XOR on the address that
// reaches the video palette read-side dpram.
video_palette video_palette_inst (
	.clk_sys      (clk_sys),
	.ce_pix       (ce_pix),
	.cpu_we       (cpu_we_palram),
	.cpu_addr     ({3'b000, cpu_addr[4:0] ^ 5'b10000}),
	.cpu_dout     (cpu_dout),
	// DIAG OFF 2026-05-30: swatch disabled to view clean graphics. Re-arm: swap back to .pen(diag_pen).
	.pen          (mixer_pen),
	// .pen          (diag_pen),
	.prom_index   (5'h00),
	.red          (core_r_hi),
	.grn          (core_g_hi),
	.blu          (core_b_hi)
);

// Mixer: priority encoding + layer blending (task 11)

deco_video_mixer deco_video_mixer_inst (
	.clk_sys                (clk_sys),
	.ce_pix                 (ce_pix),
	.fg_pen                 (fg_pen),
	.fg_opaque              (fg_opaque),
	.bg_pen                 (bg_pen),
	.bg_opaque              (bg_opaque),
	.spr_pen                (spr_pen),
	.spr_opaque             (spr_opaque),
	.mis_pen                (mis_pen),
	.mis_opaque             (mis_opaque),
	.mode_set               (mode_set_reg),
	.color_center_bot       (color_center_bot_reg),
	.color_missiles         (8'h00),
	.back_h_shift           (back_h_shift_reg),
	.back_vl_shift          (back_vl_shift_reg),
	.back_vr_shift          (back_vr_shift_reg),
	.part_h_shift           (part_h_shift_reg),
	.part_v_shift           (part_v_shift_reg),
	.center_h_shift_space   (center_h_shift_space_reg),
	.center_v_shift         (center_v_shift_reg),
	.hcnt                   (hcnt),
	.vcnt                   (vcnt),
	.out_pen                (mixer_pen),
	.out_pen_b4_modulate    (mixer_modulate)
);

// =========================================================================
// PAUSE + OUTPUT
// =========================================================================
wire        pause_cpu;
wire [23:0] rgb_pause;
wire        m_pause = 1'b0;       // TODO: wire from pause button

pause #(8,8,8,24) pause_inst (
	.clk_sys       (clk_sys),
	.reset         (reset),
	.OSD_STATUS    (OSD_STATUS),
	.user_button   (m_pause),
	.pause_request (1'b0),
	.options       (2'b00),
	.r             (core_r),
	.g             (core_g),
	.b             (core_b),
	.pause_cpu     (pause_cpu),
	.rgb_out       (rgb_pause)
);

// =========================================================================
// VIDEO OUTPUT
// =========================================================================
wire no_rotate  = status[2] | direct_video;
wire rotate_ccw = 1'b1;  // ROT270 = CCW for portrait DECO Cassette
wire flip       = 1'b0;

screen_rotate screen_rotate (.*);

arcade_video #(256,24,1) arcade_video (
	.*,
	.clk_video (clk_vid),
	.RGB_in    (rgb_pause),
	.ce_pix    (ce_pix),
	.HBlank    (video_hblank),
	.VBlank    (video_vblank),
	.HSync     (video_hsync),
	.VSync     (video_vsync),
	.fx        (3'b000)
);

assign CLK_VIDEO = clk_vid;

// =========================================================================
// AUDIO OUTPUT
// =========================================================================
assign AUDIO_L = ay_left;
assign AUDIO_R = ay_right;
assign AUDIO_S = 1'b1;

// =========================================================================
// LED STATUS
// =========================================================================
// 2026-05-18 — LED_USER as tape-motor activity indicator. tape_motor_on is
// asserted whenever MCU commands FWD or REW. Visible signal of whether the
// MCU/tape interface is alive without staring at the screen.
// DIAG-REVERT-2026-05-30: use the STICKY tape_motor_ever so a single motor pulse latches the LED
// (definitive "did the MCU ever spin the tape?" probe for the Flying Ball test). Revert: restore
// the live `tape_motor_on` line below.
// assign LED_USER  = tape_motor_on;
assign LED_USER  = tape_motor_ever;

endmodule
