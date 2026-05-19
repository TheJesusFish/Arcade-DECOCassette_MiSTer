/*============================================================================
  Type 1 Dongle — Bit Permutation + Optional PROM Lookup (Task 19)

  DECO Cassette dongle type 1 implements jumpered bit permutation via
  m_type1_inmap and m_type1_outmap. Each of 8 input bits is permuted to
  a location specified by inmap, optionally routed through a PROM or
  latched, then permuted to output location via outmap.

  Truth source: decocass_m.cpp decocass_type1_r() lines 266-339.
  MAKE_MAP macro: decocass_m.cpp lines 18-29.
  Per-game maps: decocass_m.cpp lines 357-530, 1457-1577.
  Flags: decocass.h lines 26-29.

  MAKE_MAP encoding (decocass_m.cpp:18-29):
    Each of 8 input bit indices (m0–m7) is 3 bits, packed into a 24-bit field.
    Bit i of the map is at position (i * 3 + 2 : i * 3), i.e., bits [2:0] for i=0,
    bits [5:3] for i=1, ..., bits [23:21] for i=7.
    Formula: result = m0 | (m1 << 3) | (m2 << 6) | ... | (m7 << 21)
    Unpacking T1MAP(i, map): (map >> (i * 3)) & 0x7

  Type1 flags:
    T1PROM (=1)     : bit feeds PROM address (collect up to 5 bits)
    T1DIRECT (=2)   : bit passes directly from input to output
    T1LATCH (=4)    : bit comes from previous-cycle latched input
    T1LATCHINV (=8) : bit comes from inverted latched input

  Operation (decocass_m.cpp:314-331):
    1. Read MCU status byte (from UPI-41 master port).
    2. If mode=0 (even address), perform bit permutation:
       a. For each of 8 bits, check m_type1_map[i]:
          - T1PROM: collect bit from input[inmap(i)], accumulate as PROM addr bit.
          - T1LATCH: output[outmap(i)] = latch1[inmap(i)]
          - T1LATCHINV: output[outmap(i)] = ~latch1[inmap(i)]
          - T1DIRECT: output[outmap(i)] = input[inmap(i)]
       b. If T1PROM bits present, read PROM at computed address; place PROM bits
          into output according to outmap.
    3. Latch the original input for next cycle.

  Lock'n'Chase (clocknch) at decocass_m.cpp:1518–1525:
    type1_map     = type1_latch_26_pass_3_inv_2_table
    inmap/outmap  = MAKE_MAP(0,1,3,2,4,5,6,7)  [swap bits 2↔3]
    Flags:         {P,P,LI,D,P,P,L,P}

============================================================================*/

`timescale 1 ps / 1 ps

module dongle_type1 (
    input  wire        clk_sys,
    input  wire        ce_hclk4,
    input  wire        reset,

    input  wire        cpu_re,
    input  wire        cpu_we,
    input  wire [7:0]  cpu_addr_lo,
    input  wire [7:0]  cpu_dout,
    output reg  [7:0]  cpu_din_full,        // 2026-05-18: 8-bit per MAME

    input  wire [3:0]  game_id,
    // 2026-05-18 — MCU host-bus registers (DBBOUT/DBBSTS), NOT P2 outputs.
    // Per MAME `decocass_type1_r`, the dongle reads `upi41_master_r(0)` for
    // the data path and `upi41_master_r(1)` for the status path.
    input  wire [7:0]  mcu_dbb_dout,
    input  wire [7:0]  mcu_dbb_sts,

    // Type-1 PROM lookup (PROM loaded at offset $01D00 in download)
    output wire [7:0]  prom_addr,
    input  wire [7:0]  prom_q
);

    // Local alias preserves the internal logic which uses 8-bit data input.
    wire [7:0] mcu_status_low = mcu_dbb_dout;

    // ========================================================================
    // Bit flag constants (decocass.h:26-29)
    // ========================================================================
    localparam T1PROM    = 4'h1;      // bit feeds PROM address
    localparam T1DIRECT  = 4'h2;      // bit passes directly
    localparam T1LATCH   = 4'h4;      // bit from latched input
    localparam T1LATCHINV= 4'h8;      // bit from inverted latched input

    // ========================================================================
    // Per-game configuration lookup
    // Extracted verbatim from decocass_m.cpp MACHINE_RESET_MEMBER functions
    // ========================================================================
    reg [23:0] inmap, outmap;
    reg  [3:0] type1_map [0:7];  // 8 elements, 4 bits each for flag type

    always @(*) begin
        case (game_id)
            // ctsttape (line 1457-1462): type1_pass_136_table, identity maps
            // Table (line 378): {P,D,P,D,P,P,D,P}
            4'h0: begin
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1PROM;
                type1_map[1] = T1DIRECT;
                type1_map[2] = T1PROM;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1DIRECT;
                type1_map[7] = T1PROM;
            end

            // cnebula (line 1464-1469): type1_nebula_table, identity maps
            // Table (line 387): {P,P,D,D,P,D,P,P}
            4'h1: begin
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1DIRECT;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1DIRECT;
                type1_map[6] = T1PROM;
                type1_map[7] = T1PROM;
            end

            // chwy (line 1472-1477): type1_latch_27_pass_3_inv_2_table, identity maps
            // Table (line 413): {P,P,LI,D,P,P,P,L}
            4'h2: begin
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1PROM;
                type1_map[7] = T1LATCH;
            end

            // cdsteljn (line 1479-1484): type1_latch_27_pass_3_inv_2_table, identity maps
            4'h3: begin
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1PROM;
                type1_map[7] = T1LATCH;
            end

            // cterrani (line 1486-1493): type1_latch_26_pass_3_inv_2_table, identity maps
            // Table (line 357): {P,P,LI,D,P,P,L,P}
            4'h4: begin
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // castfant (line 1495-1500): type1_latch_16_pass_3_inv_1_table, identity maps
            // Table (line 439): {P,LI,P,D,P,P,L,P}
            4'h5: begin
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1PROM;
                type1_map[1] = T1LATCHINV;
                type1_map[2] = T1PROM;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // csuperas (line 1502-1509): type1_latch_26_pass_3_inv_2_table, swap 4↔5
            // inmap/outmap = MAKE_MAP(0,1,2,3,5,4,6,7) = 0xE94C88
            4'h6: begin
                inmap      = 24'hE94C88;
                outmap     = 24'hE94C88;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // cmanhat (line 1511-1516): type1_latch_xab_pass_x54_table, identity maps
            // Table (line 400): {P,P,D,P,D,P,D,P}
            4'h7: begin
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1DIRECT;
                type1_map[3] = T1PROM;
                type1_map[4] = T1DIRECT;
                type1_map[5] = T1PROM;
                type1_map[6] = T1DIRECT;
                type1_map[7] = T1PROM;
            end

            // clocknch (line 1518-1525): type1_latch_26_pass_3_inv_2_table, swap 2↔3
            // PRIMARY VERIFICATION TARGET
            // inmap/outmap = MAKE_MAP(0,1,3,2,4,5,6,7) = 0xE64C88
            4'h8: begin
                inmap      = 24'hE64C88;
                outmap     = 24'hE64C88;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // cprogolf (line 1527-1534): type1_latch_26_pass_3_inv_2_table, swap 0↔1
            // inmap/outmap = MAKE_MAP(1,0,2,3,4,5,6,7) = 0xE64C81
            4'h9: begin
                inmap      = 24'hE64C81;
                outmap     = 24'hE64C81;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // cprogolfj (line 1536-1543): type1_latch_26_pass_3_inv_2_table, swap 0↔1
            4'hA: begin
                inmap      = 24'hE64C81;
                outmap     = 24'hE64C81;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // cluckypo (line 1545-1552): type1_latch_26_pass_3_inv_2_table, swap 1↔3
            // inmap/outmap = MAKE_MAP(0,3,2,1,4,5,6,7) = 0xE64298
            4'hB: begin
                inmap      = 24'hE64298;
                outmap     = 24'hE64298;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // ctisland (line 1554-1561): type1_latch_26_pass_3_inv_2_table, swap 0↔2
            // inmap/outmap = MAKE_MAP(2,1,0,3,4,5,6,7) = 0xE64C0A
            4'hC: begin
                inmap      = 24'hE64C0A;
                outmap     = 24'hE64C0A;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // ctisland3 (line 1563-1570): type1_latch_ctisland3, identity maps
            // Table (line 366): {LI,P,P,D,P,P,L,P}
            4'hD: begin
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1LATCHINV;
                type1_map[1] = T1PROM;
                type1_map[2] = T1PROM;
                type1_map[3] = T1DIRECT;
                type1_map[4] = T1PROM;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // cexplore (line 1572-1577): type1_latch_26_pass_5_inv_2_table, identity maps
            // Table (line 426): {P,P,LI,P,P,D,L,P}
            4'hE: begin
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1PROM;
                type1_map[4] = T1PROM;
                type1_map[5] = T1DIRECT;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            // Sub-mux for game_id 0xF (cocean1a/clocknchj/cfboy0a1)
            // For now, default to cocean1a (line 460).
            // Table (line 460): {P,P,LI,P,D,P,L,P}
            4'hF: begin
                // TODO(verify-with-mame): disambiguate cocean1a/clocknchj/cfboy0a1 via game ROM or status bits
                inmap      = 24'h0_76_54_32_10;
                outmap     = 24'h0_76_54_32_10;
                type1_map[0] = T1PROM;
                type1_map[1] = T1PROM;
                type1_map[2] = T1LATCHINV;
                type1_map[3] = T1PROM;
                type1_map[4] = T1DIRECT;
                type1_map[5] = T1PROM;
                type1_map[6] = T1LATCH;
                type1_map[7] = T1PROM;
            end

            default: begin
                inmap      = 24'h0;
                outmap     = 24'h0;
                type1_map[0] = 4'h0;
                type1_map[1] = 4'h0;
                type1_map[2] = 4'h0;
                type1_map[3] = 4'h0;
                type1_map[4] = 4'h0;
                type1_map[5] = 4'h0;
                type1_map[6] = 4'h0;
                type1_map[7] = 4'h0;
            end
        endcase
    end

    // ========================================================================
    // Internal registers: latched MCU data
    // ========================================================================
    reg [7:0] latch1;  // Previous cycle's MCU input byte (decocass_m.cpp:301,336)

    // ========================================================================
    // Helper: Extract 3-bit map index from a 24-bit map at bit position i
    // T1MAP(i, m) = (m >> (i * 3)) & 7  (decocass_m.cpp:32-35)
    // ========================================================================
    function [2:0] t1map_get;
        input integer i;
        input [23:0] map;
        begin
            t1map_get = (map >> (i * 3)) & 3'h7;
        end
    endfunction

    // ========================================================================
    // Main combinational logic: Read path (offset & 1 == 0)
    // Bit permutation + optional PROM/latch logic
    // (decocass_m.cpp:286-337)
    // ========================================================================
    reg [7:0] permuted;
    reg [4:0] prom_addr_int;
    integer i;
    integer prom_shift;

    always @(*) begin
        permuted = 8'h00;
        prom_addr_int = 5'h00;
        prom_shift = 0;

        // Phase 1: Collect PROM address bits from T1PROM positions in input
        // Input bits are selected by inmap indices.
        // (decocass_m.cpp:314-321)
        for (i = 0; i < 8; i = i + 1) begin
            if (type1_map[i] == T1PROM) begin
                // Collect bit from input[inmap(i)], place in PROM address at prom_shift position
                prom_addr_int[prom_shift] = mcu_status_low[t1map_get(i, inmap)];
                prom_shift = prom_shift + 1;
            end
        end

        // Phase 2: Build output using permutation + PROM/latch selection
        // Output bits are placed by outmap indices.
        // (decocass_m.cpp:325-331)
        prom_shift = 0;
        for (i = 0; i < 8; i = i + 1) begin
            case (type1_map[i])
                T1PROM: begin
                    // Place bit from PROM output at position selected by outmap
                    permuted[t1map_get(i, outmap)] = prom_q[prom_shift];
                    prom_shift = prom_shift + 1;
                end
                T1DIRECT: begin
                    // Pass input bit directly: input[inmap(i)] -> output[outmap(i)]
                    permuted[t1map_get(i, outmap)] = mcu_status_low[t1map_get(i, inmap)];
                end
                T1LATCH: begin
                    // Use latched input bit: latch1[inmap(i)] -> output[outmap(i)]
                    permuted[t1map_get(i, outmap)] = latch1[t1map_get(i, inmap)];
                end
                T1LATCHINV: begin
                    // Use inverted latched input bit: ~latch1[inmap(i)] -> output[outmap(i)]
                    permuted[t1map_get(i, outmap)] = ~latch1[t1map_get(i, inmap)];
                end
            endcase
        end
    end

    // ========================================================================
    // Output: 8-bit per MAME `decocass_type1_r` (decocass_m.cpp:266-339)
    //   $E5x0 (data path)   → full 8-bit `permuted`
    //   $E5x1 (status path) → 0x7C | (IBF<<1) | OBF
    // ========================================================================
    always @(*) begin
        if (cpu_addr_lo[0] == 1'b0) begin
            cpu_din_full = permuted;
        end else begin
            cpu_din_full = 8'h7C | {6'b0, mcu_dbb_sts[1:0]};
        end
    end

    // ========================================================================
    // Latch update on read (every read cycle updates latch)
    // (decocass_m.cpp:336)
    // ========================================================================
    always @(posedge clk_sys) begin
        if (reset) begin
            latch1 <= 8'h00;
        end else if (ce_hclk4 && cpu_re && (cpu_addr_lo[0] == 1'b0)) begin
            latch1 <= mcu_status_low;  // Latch the unmodified input for next cycle
        end
    end

    // ========================================================================
    // PROM address output
    // The 5-bit PROM address is built from T1PROM bits in the input.
    // ========================================================================
    assign prom_addr = {3'b000, prom_addr_int};  // 8-bit address, upper 3 bits zero

endmodule
