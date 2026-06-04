`timescale 1 ps / 1 ps
module pll_sound (
		input  wire refclk,
		input  wire rst,
		output wire outclk_0,
		output wire locked
	);

	pll_sound_0002 pll_inst (
		.refclk (refclk),
		.rst    (rst),
		.outclk_0 (outclk_0),
		.locked (locked)
	);

endmodule