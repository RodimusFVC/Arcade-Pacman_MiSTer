//============================================================================
//  board_template.sv - start a new Pac-Man-core board by copying this file (NOT in files.qip, never compiled).
//  Copyright (C) 2026 Rodimus
//
//  Boards never instantiate a CPU, sound chip, ROM store or board RAM. Drive the pool ports. Copy this file to start a board.
//  They live ONCE in rtl/pacman_dispatcher.sv: Z80s z80sed_0 (main) / z80sed_1 (Super Chick sound), S2650 s2650_0,
//  AY-3-8910s g_ay 0-2, SN76489s g_sn76489 0-1 (chip_pool_pkg buses), the ROM blocks (program, gfx, colour / palette
//  PROMs, Jr palette, Ali Baba clock, waveform, Super Chick sound; load decode by ioctl address in the dispatcher)
//  and the board RAM pool pr 0-6 (4K, 4K, 256, 16, 16, 16, 1K; ram_pool_pkg). New board: copy this file to
//  rtl/boards/<board>/<board>.sv, add it to files.qip, put its buses on the dispatcher's variant muxes, tie what it
//  doesn't use to '0. A RAM bigger than its block = grow the block. A RAM / chip that truly can't pool =
//  "// POOL-EXCEPTION: <reason>" on its instance line + a Pool contract row. verilator/common/pool_check.sh enforces it.
//============================================================================

module board_template
(
    input  logic        clk,            // 49.152 MHz
    input  logic        reset,          // core reset | this board inactive
    input  logic        ce6,            // 6.144 MHz pixel clock enable
    input  logic        pause,

    output chip_pool_pkg::z80sed_i_t        z80sed_0_i,
    input  chip_pool_pkg::z80sed_o_t        z80sed_0_o,
    output chip_pool_pkg::z80sed_i_t        z80sed_1_i,
    input  chip_pool_pkg::z80sed_o_t        z80sed_1_o,
    output chip_pool_pkg::s2650_i_t         s2650_0_i,
    input  chip_pool_pkg::s2650_o_t         s2650_0_o,
    output chip_pool_pkg::ay_i_t      [2:0] ay_i,
    input  chip_pool_pkg::ay_o_t      [2:0] ay_o,
    output chip_pool_pkg::sn76489_i_t [1:0] sn76489_i,
    input  chip_pool_pkg::sn76489_o_t [1:0] sn76489_o,

    output logic [15:0] prog_a,
    input  logic  [7:0] prog_q,
    output logic [15:0] gfx_b_a,
    input  logic  [7:0] gfx_b_q,

    output ram_pool_pkg::pram_i_t [6:0] pr_i,
    input  ram_pool_pkg::pram_o_t [6:0] pr_o,

    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,

    output logic signed [15:0] audio
);

assign z80sed_0_i   = '0;
assign z80sed_1_i   = '0;
assign s2650_0_i    = '0;
assign ay_i         = '0;
assign sn76489_i    = '0;
assign prog_a       = 16'd0;
assign gfx_b_a      = 16'd0;
assign pr_i         = '0;
assign video_r      = 8'd0;
assign video_g      = 8'd0;
assign video_b      = 8'd0;
assign video_hs     = 1'b0;
assign video_vs     = 1'b0;
assign video_hblank = 1'b1;
assign video_vblank = 1'b1;
assign audio        = 16'sd0;

endmodule
