//  Based on MAME pacman.cpp (Nicola Salmoria, Stephane Humbert, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module pacman_dispatcher
(
    input               clk,
    input               reset,
    input               ce6,
    input               pause,

    input         [7:0] variant,
    input         [3:0] rom_dec,
    output              sdr_req,
    output       [19:0] sdr_addr,
    input         [7:0] sdr_data,
    input               sdr_busy,

    input               wide_hblank,
    input         [3:0] gfx_dec,

    input         [7:0] in0,
    input         [7:0] in1,
    input         [7:0] dsw1,
    input         [7:0] dsw2,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               ioctl_wr0,

    input               crt_flip,
    input  signed [3:0] h_adj,
    input  signed [3:0] v_adj,

    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output              video_hs,
    output              video_vs,
    output              video_hblank,
    output              video_vblank,

    output signed [15:0] audio,

    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write
);

wire v_s26 = variant >= 8'd30 && variant <= 8'd32;
wire v_sch = variant == 8'd33;

wire prog_cs, gfx_cs, pal_cs, lut_cs, wave_cs, jr_lo_cs, jr_hi_cs, gfx2_cs, sabc_gfx_cs, s26_gfx_cs, sch_gfx_cs, sch_snd_cs;

selector rom_selector
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(prog_cs),
    .gfx_cs(gfx_cs),
    .pal_cs(pal_cs),
    .lut_cs(lut_cs),
    .wave_cs(wave_cs),
    .jr_lo_cs(jr_lo_cs),
    .jr_hi_cs(jr_hi_cs),
    .gfx2_cs(gfx2_cs),
    .sabc_gfx_cs(sabc_gfx_cs),
    .s26_gfx_cs(s26_gfx_cs),
    .sch_gfx_cs(sch_gfx_cs),
    .sch_snd_cs(sch_snd_cs)
);

wire dl_prog  = ioctl_wr0 & prog_cs;
wire dl_gfx   = ioctl_wr0 & gfx_cs;
wire dl_pal   = ioctl_wr0 & pal_cs;
wire dl_lut   = ioctl_wr0 & lut_cs;
wire dl_wave  = ioctl_wr0 & wave_cs;
wire dl_jr_lo = ioctl_wr0 & jr_lo_cs;
wire dl_jr_hi = ioctl_wr0 & jr_hi_cs;
wire dl_clock = ioctl_wr0 & gfx2_cs;
wire dl_sabc  = ioctl_wr0 & sabc_gfx_cs;
wire dl_s26   = ioctl_wr0 & s26_gfx_cs;
wire dl_sch   = ioctl_wr0 & sch_gfx_cs;
wire dl_sch_s = ioctl_wr0 & sch_snd_cs;

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////
// z80sed_0: main CPU, every Z80 board (held in reset by the watchdog and on the S2650 boards)
// T80sed holds MREQ/RD/WR through T2, so every access overlaps the CPU half of the sync bus
chip_pool_pkg::z80sed_i_t pm_z80sed_0_i, z80sed_0_i;
chip_pool_pkg::z80sed_o_t z80sed_0_o;
assign z80sed_0_i = pm_z80sed_0_i;

wire [15:0] z80sed_0_a;
wire  [7:0] z80sed_0_do;
wire        z80sed_0_m1_n, z80sed_0_mreq_n, z80sed_0_iorq_n, z80sed_0_rd_n, z80sed_0_wr_n, z80sed_0_rfsh_n;

t80sv_T80sed z80sed_0
(
    .RESET_n(z80sed_0_i.reset_n), .CLK_n(clk), .CLKEN(z80sed_0_i.ce), .WAIT_n(z80sed_0_i.wait_n),
    .INT_n(z80sed_0_i.int_n), .NMI_n(z80sed_0_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80sed_0_m1_n), .MREQ_n(z80sed_0_mreq_n), .IORQ_n(z80sed_0_iorq_n), .RD_n(z80sed_0_rd_n), .WR_n(z80sed_0_wr_n),
    .RFSH_n(z80sed_0_rfsh_n), .HALT_n(), .BUSAK_n(), .A(z80sed_0_a), .DI(z80sed_0_i.di), .DO(z80sed_0_do)
);

assign z80sed_0_o.a = z80sed_0_a;           assign z80sed_0_o.dout = z80sed_0_do;
assign z80sed_0_o.m1_n = z80sed_0_m1_n;     assign z80sed_0_o.mreq_n = z80sed_0_mreq_n; assign z80sed_0_o.iorq_n = z80sed_0_iorq_n;
assign z80sed_0_o.rd_n = z80sed_0_rd_n;     assign z80sed_0_o.wr_n = z80sed_0_wr_n;     assign z80sed_0_o.rfsh_n = z80sed_0_rfsh_n;

// z80sed_1: Super Chick sound board
chip_pool_pkg::z80sed_i_t sch_z80sed_1_i, z80sed_1_i;
chip_pool_pkg::z80sed_o_t z80sed_1_o;
assign z80sed_1_i = sch_z80sed_1_i;

wire [15:0] z80sed_1_a;
wire  [7:0] z80sed_1_do;
wire        z80sed_1_m1_n, z80sed_1_mreq_n, z80sed_1_iorq_n, z80sed_1_rd_n, z80sed_1_wr_n, z80sed_1_rfsh_n;

t80sv_T80sed z80sed_1
(
    .RESET_n(z80sed_1_i.reset_n), .CLK_n(clk), .CLKEN(z80sed_1_i.ce), .WAIT_n(z80sed_1_i.wait_n),
    .INT_n(z80sed_1_i.int_n), .NMI_n(z80sed_1_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80sed_1_m1_n), .MREQ_n(z80sed_1_mreq_n), .IORQ_n(z80sed_1_iorq_n), .RD_n(z80sed_1_rd_n), .WR_n(z80sed_1_wr_n),
    .RFSH_n(z80sed_1_rfsh_n), .HALT_n(), .BUSAK_n(), .A(z80sed_1_a), .DI(z80sed_1_i.di), .DO(z80sed_1_do)
);

assign z80sed_1_o.a = z80sed_1_a;           assign z80sed_1_o.dout = z80sed_1_do;
assign z80sed_1_o.m1_n = z80sed_1_m1_n;     assign z80sed_1_o.mreq_n = z80sed_1_mreq_n; assign z80sed_1_o.iorq_n = z80sed_1_iorq_n;
assign z80sed_1_o.rd_n = z80sed_1_rd_n;     assign z80sed_1_o.wr_n = z80sed_1_wr_n;     assign z80sed_1_o.rfsh_n = z80sed_1_rfsh_n;

// s2650_0: S2650 boards (Driving Force, Eight Ball Action, Porky)
chip_pool_pkg::s2650_i_t s26_s2650_0_i, s2650_0_i;
chip_pool_pkg::s2650_o_t s2650_0_o;
assign s2650_0_i = s26_s2650_0_i;

wire        s2650_0_req, s2650_0_wr, s2650_0_mio, s2650_0_ene, s2650_0_dc, s2650_0_intack;
wire [14:0] s2650_0_ad;
wire  [7:0] s2650_0_dw;
wire  [1:0] s2650_0_ph;

s2650sv_s2650_cpu s2650_0
(
    .clk(clk), .reset(s2650_0_i.reset), .req(s2650_0_req), .ack(s2650_0_i.ack), .ad(s2650_0_ad), .wr(s2650_0_wr),
    .dw(s2650_0_dw), .dr(s2650_0_i.dr), .mio(s2650_0_mio), .ene(s2650_0_ene), .dc(s2650_0_dc), .ph(s2650_0_ph),
    .irq(s2650_0_i.irq), .intack(s2650_0_intack), .ivec(8'h03), .sense(s2650_0_i.sense), .flag()
);

assign s2650_0_o.req = s2650_0_req;  assign s2650_0_o.ad = s2650_0_ad;    assign s2650_0_o.wr = s2650_0_wr;
assign s2650_0_o.dw = s2650_0_dw;    assign s2650_0_o.mio = s2650_0_mio;  assign s2650_0_o.ene = s2650_0_ene;
assign s2650_0_o.dc = s2650_0_dc;    assign s2650_0_o.ph = s2650_0_ph;    assign s2650_0_o.intack = s2650_0_intack;

// AY-3-8910 x 3 (jt49_bus, COMP 010): Crush Roller AY board / Dream Shopper use 0, Super Chick 0-2
chip_pool_pkg::ay_i_t [0:0] pm_ay_i;
chip_pool_pkg::ay_i_t [2:0] sch_ay_i;
chip_pool_pkg::ay_o_t [2:0] ay_o;

genvar ai;
generate
    for (ai = 0; ai < 3; ai = ai + 1) begin : g_ay
        chip_pool_pkg::ay_i_t i;
        if (ai == 0) begin : g0 assign i = v_sch ? sch_ay_i[ai] : pm_ay_i[0]; end
        else         begin : gn assign i = sch_ay_i[ai]; end
        wire [7:0] dout, a, b, c, iob;
        wire [9:0] snd;
        jt49_bus #(.COMP(3'b010)) ay
        (
            .rst_n(~reset), .clk(clk), .clk_en(i.ce), .bdir(i.bdir), .bc1(i.bc1), .din(i.din), .sel(1'b1),
            .dout(dout), .sound(snd), .A(a), .B(b), .C(c), .sample(),
            .IOA_in(i.ioa_in), .IOA_out(), .IOB_in(i.iob_in), .IOB_out(iob)
        );
        assign ay_o[ai].dout = dout; assign ay_o[ai].a = a; assign ay_o[ai].b = b; assign ay_o[ai].c = c;
        assign ay_o[ai].iob_out = iob; assign ay_o[ai].sound = snd;
    end
endgenerate

// SN76489 x 2 (sn76489sv, VARIANT 2 = SN76496): Van-Van uses 0-1, S2650 boards 0
chip_pool_pkg::sn76489_i_t [1:0] vv_sn76489_i;
chip_pool_pkg::sn76489_i_t [0:0] s26_sn76489_i;
chip_pool_pkg::sn76489_o_t [1:0] sn76489_o;

genvar si;
generate
    for (si = 0; si < 2; si = si + 1) begin : g_sn76489
        chip_pool_pkg::sn76489_i_t i;
        if (si == 0) begin : g0 assign i = v_s26 ? s26_sn76489_i[0] : vv_sn76489_i[si]; end
        else         begin : gn assign i = vv_sn76489_i[si]; end
        wire [10:0] snd;
        wire        rdy;
        sn76489sv #(.VARIANT(2)) sn76489
        (
            .rst(i.rst), .clk(clk), .ce(i.ce), .wr_n(i.wr_n), .cs_n(i.cs_n), .din(i.din), .sound(snd), .ready(rdy)
        );
        assign sn76489_o[si].sound = snd; assign sn76489_o[si].ready = rdy;
    end
endgenerate

/////////////////////////////  Shared ROM blocks  /////////////////////////////

wire [15:0] prog_a, gfx_a_a, gfx_b_a;
wire [10:0] clk_a_a, clk_b_a;
wire [12:0] sch_rom_a;
wire  [7:0] lut_a_a, lut_b_a, wave_a;
wire  [4:0] pal_a, jrpal_a;
wire  [7:0] prog_q, gfx_a_q, gfx_b_q, lut_a_q, lut_b_q, clk_a_q, clk_b_q, pal_q, jrlo_q, jrhi_q, wave_q, sch_rom_d;

dpram_dc #(.widthad_a(16)) prog_rom
(
    .clock_a(clk), .address_a(ioctl_addr[15:0]), .data_a(ioctl_dout), .wren_a(dl_prog),
    .clock_b(clk), .address_b(prog_a), .q_b(prog_q)
);
dpram_dc #(.widthad_a(16)) gfx_rom
(
    .clock_a(clk), .address_a(gfx_a_a), .data_a(ioctl_dout), .wren_a(dl_gfx | (dl_sabc & ~ioctl_addr[13]) | dl_s26 | dl_sch), .q_a(gfx_a_q),
    .clock_b(clk), .address_b(gfx_b_a), .q_b(gfx_b_q)
);
dpram_dc #(.widthad_a(8)) col_rom_4a
(
    .clock_a(clk), .address_a(lut_a_a), .data_a(ioctl_dout), .wren_a(dl_lut), .q_a(lut_a_q),
    .clock_b(clk), .address_b(lut_b_a), .q_b(lut_b_q)
);
dpram_dc #(.widthad_a(11)) clock_rom
(
    .clock_a(clk), .address_a(clk_a_a), .data_a(ioctl_dout), .wren_a(dl_clock), .q_a(clk_a_q),
    .clock_b(clk), .address_b(clk_b_a), .q_b(clk_b_q)
);
dpram_dc #(.widthad_a(5)) col_rom_7f
(
    .clock_a(clk), .address_a(ioctl_addr[4:0]), .data_a(ioctl_dout), .wren_a(dl_pal),
    .clock_b(clk), .address_b(pal_a), .q_b(pal_q)
);
dpram_dc #(.widthad_a(5)) jr_pal_lo
(
    .clock_a(clk), .address_a(ioctl_addr[4:0]), .data_a(ioctl_dout), .wren_a(dl_jr_lo),
    .clock_b(clk), .address_b(jrpal_a), .q_b(jrlo_q)
);
dpram_dc #(.widthad_a(5)) jr_pal_hi
(
    .clock_a(clk), .address_a(ioctl_addr[4:0]), .data_a(ioctl_dout), .wren_a(dl_jr_hi),
    .clock_b(clk), .address_b(jrpal_a), .q_b(jrhi_q)
);
dpram_dc #(.widthad_a(8)) wave_rom
(
    .clock_a(clk), .address_a(ioctl_addr[7:0]), .data_a(ioctl_dout), .wren_a(dl_wave),
    .clock_b(clk), .address_b(wave_a), .q_b(wave_q)
);
dpram_dc #(.widthad_a(13)) sch_rom
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(dl_sch_s & ioctl_addr[14:13] == 2'd0),
    .clock_b(clk), .address_b(sch_rom_a), .q_b(sch_rom_d)
);

/////////////////////////////  Board RAM pool  /////////////////////////////
//   pr 0  4K   work / video RAM 4000-4FFF (port B: hiscore)
//   pr 1  4K   extra RAM (Pengo on Pac-Man F000, Ali Baba 9000)
//   pr 2  256  sprite line buffer
//   pr 3  16   sprite X/Y registers
//   pr 4  16   WSG volume RAM
//   pr 5  16   WSG frequency RAM
//   pr 6  1K   Super Chick sound RAM / S2650 column scroll RAM

ram_pool_pkg::pram_i_t [6:0] pr_i, pool_i;
ram_pool_pkg::pram_o_t [6:0] pr_o;

assign pool_i[6:1]      = pr_i[6:1];
assign pool_i[0].a_addr = pr_i[0].a_addr;
assign pool_i[0].a_d    = pr_i[0].a_d;
assign pool_i[0].a_we   = pr_i[0].a_we;
assign pool_i[0].b_addr = {4'd0, hs_address[11:0]};
assign pool_i[0].b_d    = hs_data_in;
assign pool_i[0].b_we   = hs_write;
assign hs_data_out      = pr_o[0].b_q;

dpram_dc #(.widthad_a(12)) pr_0
(
    .clock_a(clk), .wren_a(pool_i[0].a_we), .address_a(pool_i[0].a_addr[11:0]), .data_a(pool_i[0].a_d), .q_a(pr_o[0].a_q),
    .clock_b(clk), .wren_b(pool_i[0].b_we), .address_b(pool_i[0].b_addr[11:0]), .data_b(pool_i[0].b_d), .q_b(pr_o[0].b_q)
);
dpram_dc #(.widthad_a(12)) pr_1
(
    .clock_a(clk), .wren_a(pool_i[1].a_we), .address_a(pool_i[1].a_addr[11:0]), .data_a(pool_i[1].a_d), .q_a(pr_o[1].a_q),
    .clock_b(clk), .wren_b(pool_i[1].b_we), .address_b(pool_i[1].b_addr[11:0]), .data_b(pool_i[1].b_d), .q_b(pr_o[1].b_q)
);
dpram_dc #(.widthad_a(8)) pr_2
(
    .clock_a(clk), .wren_a(pool_i[2].a_we), .address_a(pool_i[2].a_addr[7:0]), .data_a(pool_i[2].a_d), .q_a(pr_o[2].a_q),
    .clock_b(clk), .wren_b(pool_i[2].b_we), .address_b(pool_i[2].b_addr[7:0]), .data_b(pool_i[2].b_d), .q_b(pr_o[2].b_q)
);
dpram_dc #(.widthad_a(4)) pr_3
(
    .clock_a(clk), .wren_a(pool_i[3].a_we), .address_a(pool_i[3].a_addr[3:0]), .data_a(pool_i[3].a_d), .q_a(pr_o[3].a_q),
    .clock_b(clk), .wren_b(pool_i[3].b_we), .address_b(pool_i[3].b_addr[3:0]), .data_b(pool_i[3].b_d), .q_b(pr_o[3].b_q)
);
dpram_dc #(.widthad_a(4)) pr_4
(
    .clock_a(clk), .wren_a(pool_i[4].a_we), .address_a(pool_i[4].a_addr[3:0]), .data_a(pool_i[4].a_d), .q_a(pr_o[4].a_q),
    .clock_b(clk), .wren_b(pool_i[4].b_we), .address_b(pool_i[4].b_addr[3:0]), .data_b(pool_i[4].b_d), .q_b(pr_o[4].b_q)
);
dpram_dc #(.widthad_a(4)) pr_5
(
    .clock_a(clk), .wren_a(pool_i[5].a_we), .address_a(pool_i[5].a_addr[3:0]), .data_a(pool_i[5].a_d), .q_a(pr_o[5].a_q),
    .clock_b(clk), .wren_b(pool_i[5].b_we), .address_b(pool_i[5].b_addr[3:0]), .data_b(pool_i[5].b_d), .q_b(pr_o[5].b_q)
);
dpram_dc #(.widthad_a(10)) pr_6
(
    .clock_a(clk), .wren_a(pool_i[6].a_we), .address_a(pool_i[6].a_addr[9:0]), .data_a(pool_i[6].a_d), .q_a(pr_o[6].a_q),
    .clock_b(clk), .wren_b(pool_i[6].b_we), .address_b(pool_i[6].b_addr[9:0]), .data_b(pool_i[6].b_d), .q_b(pr_o[6].b_q)
);

/////////////////////////////  Boards  /////////////////////////////

pacman_board board
(
    .clk(clk), .reset(reset), .ce6(ce6), .pause(pause),
    .variant(variant), .rom_dec(rom_dec),
    .sdr_req(sdr_req), .sdr_addr(sdr_addr), .sdr_data(sdr_data), .sdr_busy(sdr_busy),
    .wide_hblank(wide_hblank), .gfx_dec(gfx_dec),
    .in0(in0), .in1(in1), .dsw1(dsw1), .dsw2(dsw2),
    .ioctl_addr(ioctl_addr), .dl_sabc(dl_sabc), .dl_s26(dl_s26), .dl_sch(dl_sch),
    .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),
    .video_r(video_r), .video_g(video_g), .video_b(video_b), .video_hs(video_hs), .video_vs(video_vs),
    .video_hblank(video_hblank), .video_vblank(video_vblank),
    .audio(audio),
    .pm_z80sed_0_i(pm_z80sed_0_i), .z80sed_0_o(z80sed_0_o), .sch_z80sed_1_i(sch_z80sed_1_i), .z80sed_1_o(z80sed_1_o),
    .s26_s2650_0_i(s26_s2650_0_i), .s2650_0_o(s2650_0_o),
    .pm_ay_i(pm_ay_i), .sch_ay_i(sch_ay_i), .ay_o(ay_o),
    .vv_sn76489_i(vv_sn76489_i), .s26_sn76489_i(s26_sn76489_i), .sn76489_o(sn76489_o),
    .prog_a(prog_a), .prog_q(prog_q),
    .gfx_a_a(gfx_a_a), .gfx_a_q(gfx_a_q), .gfx_b_a(gfx_b_a), .gfx_b_q(gfx_b_q),
    .lut_a_a(lut_a_a), .lut_a_q(lut_a_q), .lut_b_a(lut_b_a), .lut_b_q(lut_b_q),
    .clk_a_a(clk_a_a), .clk_a_q(clk_a_q), .clk_b_a(clk_b_a), .clk_b_q(clk_b_q),
    .pal_a(pal_a), .pal_q(pal_q), .jrpal_a(jrpal_a), .jrlo_q(jrlo_q), .jrhi_q(jrhi_q),
    .wave_a(wave_a), .wave_q(wave_q), .sch_rom_a(sch_rom_a), .sch_rom_d(sch_rom_d),
    .pr_i(pr_i), .pr_o(pr_o)
);

endmodule

//============================================================================
//
//  Pac-Man ROM loader (per-game ROM layout decode for the ioctl download)
// Based on MAME pacman.cpp (Nicola Salmoria, Stephane Humbert, BSD-3-Clause)
//
//============================================================================

// ioctl index 0 (MRA), all images stored exactly as dumped:
//   0x00000 - 0x0FFFF  main CPU          "maincpu"
//   0x10000 - 0x13FFF  tiles + sprites   "gfx1"
//   0x14000 - 0x1401F  palette PROM      "proms" 0x000
//   0x14020 - 0x1411F  colour lookup     "proms" 0x020 (Pengo's 1K lookup occupies up to 0x1441F)
//   0x14600 - 0x146FF  Jr palette 9E     "proms" low nibbles (ROM_LOAD_NIB_LOW)
//   0x14700 - 0x147FF  Jr palette 9F     "proms" high nibbles (ROM_LOAD_NIB_HIGH)
//   0x14800 - 0x148FF  waveform PROM     "namco" 0x000 (0x100 timing PROM is not loaded)
//   0x15000 - 0x15FFF  Ali Baba clock    "gfx2" (the same 2K ROM loaded twice)
//   0x18000 - 0x1FFFF  S2650 boards      "gfx1" (32K: tiles 0x0000, sprites 0x4000)
//   0x20000 - 0x3FFFF  Super ABC gfx     "user1" (descrambled into the 64K gfx store as it loads)
//   0x40000 - 0x4FFFF  Super Chick       "gfx1" (64K, 4bpp: planes 2/3 in the upper half)
//   0x50000 - 0x57FFF  Super Chick       "audiocpu"
//
// ioctl index 2: SDRAM (Rock Tris / Big Bucks "user1" questions, Super ABC "maincpu")
//
// ioctl index 1: board variant, flags and input map (see the top level)
// ioctl indexes 3 and 4 are reserved for hiscore config and NVRAM

module selector
(
    input  logic [24:0] ioctl_addr,
    output logic        prog_cs,
    output logic        gfx_cs,
    output logic        pal_cs,
    output logic        lut_cs,
    output logic        wave_cs,
    output logic        jr_lo_cs,
    output logic        jr_hi_cs,
    output logic        gfx2_cs,
    output logic        sabc_gfx_cs,
    output logic        s26_gfx_cs,
    output logic        sch_gfx_cs,
    output logic        sch_snd_cs
);
    always_comb begin
        {prog_cs, gfx_cs, pal_cs, lut_cs, wave_cs, jr_lo_cs, jr_hi_cs, gfx2_cs, sabc_gfx_cs, s26_gfx_cs, sch_gfx_cs, sch_snd_cs} = '0;

        if      (ioctl_addr < 25'h10000) prog_cs = 1'b1;
        else if (ioctl_addr < 25'h14000) gfx_cs  = 1'b1;
        else if (ioctl_addr < 25'h14020) pal_cs  = 1'b1;
        else if (ioctl_addr < 25'h14120) lut_cs  = 1'b1;
        else if (ioctl_addr >= 25'h14600 && ioctl_addr < 25'h14620) jr_lo_cs = 1'b1;
        else if (ioctl_addr >= 25'h14700 && ioctl_addr < 25'h14720) jr_hi_cs = 1'b1;
        else if (ioctl_addr >= 25'h14800 && ioctl_addr < 25'h14900) wave_cs = 1'b1;
        else if (ioctl_addr >= 25'h15000 && ioctl_addr < 25'h16000) gfx2_cs = 1'b1;
        else if (ioctl_addr >= 25'h18000 && ioctl_addr < 25'h20000) s26_gfx_cs = 1'b1;
        else if (ioctl_addr >= 25'h20000 && ioctl_addr < 25'h40000) sabc_gfx_cs = 1'b1;
        else if (ioctl_addr >= 25'h40000 && ioctl_addr < 25'h50000) sch_gfx_cs = 1'b1;
        else if (ioctl_addr >= 25'h50000 && ioctl_addr < 25'h58000) sch_snd_cs = 1'b1;
    end
endmodule
