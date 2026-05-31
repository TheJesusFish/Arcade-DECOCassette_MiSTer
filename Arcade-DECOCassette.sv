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
	.sync_o          (),
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
wire [7:0] core_r = {core_r_hi, core_r_hi};
wire [7:0] core_g = {core_g_hi, core_g_hi};
wire [7:0] core_b = {core_b_hi, core_b_hi};

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
	.pen          (mixer_pen),
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
assign LED_USER  = tape_motor_on;

endmodule
