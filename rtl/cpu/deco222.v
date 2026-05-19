// DECO-222 wrapper around T65 6502 core
// Implements opcode fetch data-bus encryption: D1 and D6 are swapped
// on M1/sync cycles only. Data fetches and write cycles pass through unmodified.
//
// Reference: MAME src/devices/cpu/m6502/deco222.cpp
//   bswap = ((byte & 0xBD) | ((byte & 0x40) >> 5) | ((byte & 0x02) << 5))
//   i.e. swap bits D1 and D6

module deco222 (
    input  wire        clk_sys,
    input  wire        ce,            // = ce_hclk4 (750 kHz)
    input  wire        reset,

    input  wire        nmi_n,
    input  wire        irq_n,
    input  wire        rdy,

    output wire [15:0] addr,
    input  wire [7:0]  di,
    output wire [7:0]  do,
    output wire        rw_n,          // 1 = read, 0 = write
    output wire        sync           // T65 SYNC: 1 on opcode fetch
);

    wire [7:0] di_eff;

    // D1/D6 swap, only on opcode fetch (sync=1)
    // Reconstructed from MAME formula: keeps bits {7,5,4,3,2,0}, swaps bits {1,6}
    assign di_eff = sync
        ? { di[7], di[1], di[5:2], di[6], di[0] }
        : di;

    // Instantiate T65 6502 core
    T65 cpu (
        .Mode      (2'b00),               // 6502 mode
        .Res_n     (~reset),              // active-low reset
        .Enable    (ce),                  // clock enable
        .Clk       (clk_sys),             // system clock
        .Rdy       (rdy),                 // ready (not used, always 1)
        .Abort_n   (1'b1),                // 65C816 abort, unused
        .IRQ_n     (irq_n),               // active-low interrupt request
        .NMI_n     (nmi_n),               // active-low non-maskable interrupt
        .SO_n      (1'b1),                // 6502 set-overflow, unused
        .R_W_n     (rw_n),                // read(1) / write(0) output
        .Sync      (sync),                // opcode fetch strobe
        .EF        (),                    // 65C02/816 stuff, unused
        .MF        (),
        .XF        (),
        .ML_n      (),
        .VP_n      (),
        .VDA       (),
        .VPA       (),
        .A         (addr),                // 16-bit address bus (A23..A8 unused)
        .DI        (di_eff),              // data in (munged for opcode fetch)
        .DO        (do),                  // data out
        .Regs      (),                    // debug register read-out, unused
        .DEBUG     (),                    // debug port, unused
        .NMI_ack   ()                     // debug NMI ack, unused
    );

endmodule
