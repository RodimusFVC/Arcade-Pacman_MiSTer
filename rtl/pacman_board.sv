//============================================================================
//
//  Pac-Man board (Namco / Midway)
//
//  Timing, sync bus and video model ported from "A simulation model of
//  Pacman hardware", Copyright (c) MikeJ - January 2006 (www.fpgaarcade.com),
//  BSD licence; MiSTer merge by Alexey Melnikov (Sorgelig).
//  Memory maps per MAME pacman.cpp (Nicola Salmoria).
//
//============================================================================

module pacman_board
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               ce6,            // 6.144 MHz pixel clock enable
    input               pause,

    input         [7:0] variant,        // 0 Pac-Man, 1 Ms. Pac-Man aux board, 2 Zola-Puc (mschamp), 3 Ms. Pac-Man Twin,
                                        // 4 ROM at 8000 (woodpek), 5 + Piranha vector, 6 N. Mouse vector, 7 Ms. Pac-Man II,
                                        // 8 Make Trax protection, 9 Make Trax bootleg protection, 10 Crush Roller AY board,
                                        // 11-13 Epos daughterboard (The Glob, Atlantic City Action, Eeekk!),
                                        // 14 Cannon Ball, 15 Number Crash, 16 Pengo on Pac-Man, 17 Club Pac-Man,
                                        // 18 Dream Shopper (AY, NMI), 19 Van-Van (2 x SN76496, NMI), 20 Jr. Pac-Man,
                                        // 21 Pengo, 22 Pengo 315-5010, 23 Pengo 315-5007, 24 Jr. Pac-Man on Pengo board,
                                        // 25 Birdiy, 26 Ali Baba, 27 Rock Tris, 28 Big Bucks, 29 Super ABC (SDRAM),
                                        // 30-32 S2650 daughterboard (Driving Force, Eight Ball Action, Porky), 33 Super Chick
    input         [3:0] rom_dec,        // CPU ROM decode: 0 none, 1 Eyes, 2 Pac-Man Plus, 3 Jump Shot, 4 Super Glob,
                                        // 5 D3/D4 (mspackpls), 6 A0/A1 in 1000-1FFF (mspacmbe), 7 page-inverted (mspacmbn),
                                        // 8 D6/D7 (clubpacma), 9 D0/D6 (8bpm), 10 D0/D4 (porky)
    // large ROMs in SDRAM (rtl/ram_rom/pacman_sdrom.sv): the CPU waits until the byte is back
    output              sdr_req,
    output       [19:0] sdr_addr,
    input         [7:0] sdr_data,
    input               sdr_busy,

    input               wide_hblank,    // Sigma / Sanritsu boards: 256 px wide, hblank long enough for all 8 sprites
    input         [3:0] gfx_dec,        // [0] D4/D6 + A0/A2 swap (Eyes, Woodpecker), [1] Ponpoko order, [2] RBG palette,
                                        // [3] planes split across ROM halves (crush4)

    input         [7:0] in0,            // 5000
    input         [7:0] in1,            // 5040
    input         [7:0] dsw1,           // 5080
    input         [7:0] dsw2,           // 50C0

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               ioctl_wr0,      // ioctl index 0

    input               crt_flip,

    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output reg          video_hs = 1'b0,
    output              video_vs,
    output reg          video_hblank = 1'b1,
    output reg          video_vblank = 1'b1,

    output signed [15:0] audio,

    // hiscore: second port on the 4000-4FFF RAM while the CPU is paused
    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write
);

//------------------------------------------------------- ROM load map --------------------------------------------------------//

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

wire v_ms    = variant == 8'd1;
wire v_champ = variant == 8'd2;
wire v_twin  = variant == 8'd3;
wire v_wood  = variant == 8'd4 || variant == 8'd5 || variant == 8'd7;
wire v_pir   = variant == 8'd5;
wire v_mouse = variant == 8'd6;
wire v_msii  = variant == 8'd7;
wire v_mt    = variant == 8'd8;
wire v_mb    = variant == 8'd9;
wire v_crs   = variant == 8'd10;
wire v_epos  = variant >= 8'd11 && variant <= 8'd13;
wire v_cball = variant == 8'd14;
wire v_numc  = variant == 8'd15;
wire v_pengo = variant == 8'd16;
wire v_club  = variant == 8'd17;
wire v_dshop = variant == 8'd18;
wire v_van   = variant == 8'd19;
wire v_jr    = variant == 8'd20;
wire v_jrbl  = variant == 8'd24;
wire v_sch   = variant == 8'd33;                                  // Super Chick (Pengo hack, Penta + extra layer)
wire v_pgb   = (variant >= 8'd21 && variant <= 8'd24) | v_sch;  // Sega Pengo board: I/O at 9000 in Pengo order
wire jr_tm   = v_jr | v_jrbl;
wire v_bird  = variant == 8'd25;
wire v_alib  = variant == 8'd26;
wire v_rt    = variant == 8'd27;
wire v_bb    = variant == 8'd28;
wire v_sabc  = variant == 8'd29;                                  // Jr. Pac-Man scrolling playfield
wire v_s26   = variant >= 8'd30 && variant <= 8'd32;          // S2650 in the Z80 socket
wire v_nmi   = v_dshop | v_van;                         // vblank drives NMI, gated by latch Q0
wire rom_hi  = v_wood | v_numc | v_club | v_dshop | v_van;   // ROM at 8000-BFFF too, no A15 mirror
wire ram_48  = v_cball | v_dshop | v_van | v_pengo | v_jr | v_pgb | v_sabc;       // 4800-4BFF populated

//------------------------------------------------------- Video timing --------------------------------------------------------//

// H counts 080-1FF (384), V counts 0F8-1FF (264); 60.61 Hz
reg [8:0] hcnt = 9'h080;
reg [8:0] vcnt = 9'h0F8;
reg       hblank = 1'b1;

wire vcnt_step    = (hcnt == 9'h0AF);
wire rising_vblank = vcnt_step & (vcnt == 9'h1EF);

always @(posedge clk) begin
    if (ce6) begin
        hcnt <= (hcnt == 9'h1FF) ? 9'h080 : hcnt + 9'd1;
        if (vcnt_step) vcnt <= (vcnt == 9'h1FF) ? 9'h0F8 : vcnt + 9'd1;

        if      (hcnt == 9'h097) video_hblank <= 1'b1;
        else if (hcnt == (wide_hblank ? 9'h1FF : 9'h08F)) hblank <= 1'b1;
        else if (hcnt == (wide_hblank ? 9'h0FF : 9'h0EF)) hblank <= 1'b0;
        else if (hcnt == 9'h0F7) video_hblank <= 1'b0;

        if      (hcnt == 9'h0AF) video_hs <= 1'b1;
        else if (hcnt == 9'h0CF) video_hs <= 1'b0;

        if (vcnt_step) begin
            if      (vcnt == 9'h1EF) video_vblank <= 1'b1;
            else if (vcnt == 9'h10F) video_vblank <= 1'b0;
        end
    end
end

assign video_vs = ~vcnt[8];

//----------------------------------------------------------- CPU --------------------------------------------------------------//

wire        cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n;
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
wire        z80_m1_n, z80_mreq_n, z80_iorq_n, z80_rd_n, z80_wr_n, z80_rfsh_n;
wire [15:0] z80_addr;
wire  [7:0] z80_dout;
reg   [7:0] cpu_din;
reg         cpu_int_n = 1'b1;
wire        sb_wait_n;

reg   [7:0] control_reg = 8'd0;         // LS259 at 8K: 0 IRQ enable, 1 sound enable, 3 flip, 7 coin counter
reg   [4:0] watchdog = 5'd0;
wire        watchdog_reset = (watchdog == 5'd16);

// T80sed holds MREQ/RD/WR through T2, so every access overlaps the CPU half of the sync bus
T80sed z80
(
    .RESET_n(~(reset | watchdog_reset | v_s26)),
    .CLK_n(clk),
    .CLKEN(ce6 & hcnt[0] & ~pause),
    .WAIT_n(sb_wait_n & ~sdr_busy),
    .INT_n(cpu_int_n | v_nmi),
    .NMI_n(cpu_int_n | ~v_nmi),
    .BUSRQ_n(1'b1),
    .M1_n(z80_m1_n),
    .MREQ_n(z80_mreq_n),
    .IORQ_n(z80_iorq_n),
    .RD_n(z80_rd_n),
    .WR_n(z80_wr_n),
    .RFSH_n(z80_rfsh_n),
    .HALT_n(),
    .BUSAK_n(),
    .A(z80_addr),
    .DI(cpu_din),
    .DO(z80_dout)
);

// S2650 daughterboard (MAME s2650games): each access is registered on ack (every 12 pixels) and replayed on the Z80 socket
wire        s26_req, s26_wr, s26_mio, s26_ene, s26_dc, s26_intack;
wire [14:0] s26_ad;
wire  [7:0] s26_dw;
wire  [1:0] s26_ph;
wire  [7:0] s26_dr;
reg   [1:0] s26_div = 2'd0;
reg         s26_new = 1'b0, s26_req_t = 1'b0, s26_mio_t = 1'b1, s26_ene_t = 1'b0, s26_dc_t = 1'b0;
reg         s26_act = 1'b0, s26_io = 1'b0, s26_ene_r = 1'b0, s26_w = 1'b0, s26_sn_w = 1'b0, s26_int = 1'b0;
reg  [14:0] s26_a = 15'd0, s26_lastcode = 15'd0;
reg   [7:0] s26_d = 8'd0;
reg         s26_pbank = 1'b0;                              // Porky: 15C7 D0 selects the upper 32K of program ROM

wire s26_ack = v_s26 & ce6 & ~pause & hcnt[1:0] == 2'b00 & s26_div == 2'd0;

always @(posedge clk) begin
    if (ce6 && hcnt[1:0] == 2'b00) s26_div <= (s26_div == 2'd2) ? 2'd0 : s26_div + 2'd1;

    s26_new <= s26_ack;
    if (s26_ack) {s26_req_t, s26_mio_t, s26_ene_t, s26_dc_t} <= {s26_req, s26_mio, s26_ene, s26_dc};
    if (reset | watchdog_reset | ~v_s26) begin              // the CPU leaves reset executing the byte at 0000
        s26_act   <= 1'b1;
        s26_io    <= 1'b0;
        s26_a     <= 15'd0;
        s26_w     <= 1'b0;
    end
    else if (s26_new) begin
        s26_act   <= s26_req_t;
        s26_io    <= ~s26_mio_t;
        s26_ene_r <= s26_ene_t;
        s26_a     <= s26_ad;
        s26_w     <= s26_wr;
        s26_d     <= s26_dw;
        if (s26_req_t && s26_mio_t && s26_ph == 2'b00) s26_lastcode <= s26_ad;
    end
    s26_sn_w <= s26_new & s26_req_t & ~s26_mio_t & s26_wr & ~s26_ene_t & s26_dc_t;   // WRTD: SN76496

    if (reset | ~v_s26 | s26_intack) s26_int <= 1'b0;
    else if (ce6 & rising_vblank)    s26_int <= 1'b1;

    if (reset | ~v_s26) s26_pbank <= 1'b0;
    else if (ce6 && variant == 8'd32 && s26_act && !s26_io && s26_w && s26_a[12:0] == 13'h15C7) s26_pbank <= s26_d[0];
end

s2650_cpu s2650
(
    .clk(clk),
    .reset(reset | watchdog_reset | ~v_s26),
    .req(s26_req),
    .ack(s26_ack),
    .ad(s26_ad),
    .wr(s26_wr),
    .dw(s26_dw),
    .dr(s26_dr),
    .mio(s26_mio),
    .ene(s26_ene),
    .dc(s26_dc),
    .ph(s26_ph),
    .irq(s26_int),
    .intack(s26_intack),
    .ivec(8'h03),
    .sense(~video_vblank),
    .flag()
);

// extended port 1 = protection, answered by program counter (MAME pc() = REDE address + 2 = operand address + 1)
wire [14:0] s26_pc = s26_lastcode + 15'd1;
wire        s26_prot = variant == 8'd30 ? (s26_pc == 15'h0030 || s26_pc == 15'h0291) :
                       variant == 8'd31 ? (s26_pc == 15'h0030 || s26_pc == 15'h0466) : s26_pc == 15'h0034;
wire  [7:0] s26_io_q = {7'd0, s26_ene_r & s26_a[7:0] == 8'h01 & s26_prot};

wire [15:0] s26_zaddr = ~s26_a[12]                 ? {2'b00, s26_a[13:0]} :
                        s26_a[11:10] == 2'b00       ? {11'b0100_0100_000, s26_a[4:0]} :
                        s26_a[11:10] == 2'b10       ? {6'b010000, s26_a[9:0]} :
                        s26_a[11:10] == 2'b11       ? {6'b010011, s26_a[9:0]} :
                        s26_a[8]                    ? {8'h50, s26_a[7:0]} : {8'h48, s26_a[7:0]};   // 1400: daughterboard

wire s26_mem = s26_act & ~s26_io;
assign cpu_m1_n   = v_s26 | z80_m1_n;
assign cpu_mreq_n = v_s26 ? ~s26_mem : z80_mreq_n;
assign cpu_iorq_n = v_s26 | z80_iorq_n;
assign cpu_rd_n   = v_s26 ? ~(s26_mem & ~s26_w) : z80_rd_n;
assign cpu_wr_n   = v_s26 ? ~(s26_mem & s26_w) : z80_wr_n;
assign cpu_rfsh_n = v_s26 | z80_rfsh_n;
assign cpu_addr   = v_s26 ? s26_zaddr : z80_addr;
assign cpu_dout   = v_s26 ? s26_d : z80_dout;

// Birdiy: Q1 = IRQ enable, sound always on (MAME); Ali Baba: latch 2 at 50C0, Q0 sound, Q1 flip, Q2 IRQ
wire c_int   = v_bird ? control_reg[1] : v_alib ? control_reg[2] : control_reg[0];
wire c_sound = v_bird ? 1'b1 : v_alib ? control_reg[0] : control_reg[1];
wire c_flip  = ((v_alib ? control_reg[1] : control_reg[3]) & ~v_numc & ~v_sch) ^ crt_flip;

// vblank IRQ held until the game clears the enable latch; watchdog = 16 frames
always @(posedge clk) begin
    if (ce6) begin
        if (!c_int)             cpu_int_n <= 1'b1;
        else if (rising_vblank | bb_tick) cpu_int_n <= 1'b0;

        if (reset | wdr_w | pause) watchdog <= 5'd0;
        else if (rising_vblank)    watchdog <= watchdog_reset ? 5'd0 : watchdog + 5'd1;
    end
end

//------------------------------------------------------- Sync bus ------------------------------------------------------------//

// 4000-7FFF (A15 unused): CPU owns the bus while 2H is low, video while 2H is high; reads wait out the video half
// Twin: 6000-7FFF mirrors ROM 2000-3FFF; Pengo on Pac-Man: ROM 0000-7FFF, sync bus 8000-9FFF, work RAM F000-FFFF
wire rom_cs = v_sch   ? ~cpu_addr[15] | cpu_addr[15:13] == 3'b111 :                   // Super Chick: 0000-7FFF, E000-FFFF
              (v_pengo | v_pgb) ? ~cpu_addr[15] :
              v_rt    ? ~cpu_addr[14] | cpu_addr[15] | cpu_addr[13] :                 // Rock Tris: 6000-7FFF ROM, 8000-FFFF questions
              v_bb    ? ~cpu_addr[14] & (~cpu_addr[15] | ~cpu_addr[13]) :             // Big Bucks: 0000-3FFF, 8000-9FFF
              v_alib  ? ~cpu_addr[14] & ~(cpu_addr[15] & ~cpu_addr[13] & cpu_addr[12]) :   // Ali Baba: RAM at 9000-9FFF
              v_jr    ? ~cpu_addr[14] | (cpu_addr[15] & ~cpu_addr[13]) :            // Jr: 0000-3FFF, 8000-DFFF
                        ~cpu_addr[14] | (v_twin & ~cpu_addr[15] & cpu_addr[13]);
wire xram_cs = (v_pengo & cpu_addr[15:12] == 4'hF) | (v_alib & cpu_addr[15:12] == 4'h9);
wire sb_cs  = ~cpu_mreq_n & cpu_rfsh_n & ((v_pengo | v_pgb) ? cpu_addr[15:13] == 3'b100 :
                                          v_jr    ? cpu_addr[15:14] == 2'b01  :
                                          (v_rt | v_bb) ? cpu_addr[15:13] == 3'b010 : ~rom_cs);   // no mirrors
wire sb_stb = sb_cs & ~hcnt[1];
wire sb_wr  = sb_stb & cpu_rd_n;
assign sb_wait_n = ~(sb_cs & hcnt[1] & ~cpu_rd_n);

wire io_sel = sb_stb & cpu_addr[12];
// Pengo board: 9000-901F sound, 9020-902F sprite X/Y, 9040-9047 latch, 9070 watchdog; reads DSW2/DSW1/IN1/IN0 at 00/40/80/C0
wire out_w  = io_sel &  sb_wr & (v_pgb  ? cpu_addr[7:3] == 5'b01000 :
                                 v_alib ? cpu_addr[7:6] == 2'd3 && cpu_addr[5:3] == 3'd0 : cpu_addr[7:6] == 2'd0);   // latch
wire grp_w  = io_sel &  sb_wr & cpu_addr[7:6] == 2'd1;          // 5040-507F
wire wdr_w  = io_sel &  sb_wr & (v_pgb  ? cpu_addr[7:0] == 8'h70 :
                                 v_alib ? cpu_addr[7:6] == 2'd0 && cpu_addr[2:0] == 3'd0 : cpu_addr[7:6] == 2'd3);   // watchdog
wire in0_r  = io_sel & ~sb_wr & cpu_addr[7:6] == (v_pgb ? 2'd3 : 2'd0);
wire in1_r  = io_sel & ~sb_wr & cpu_addr[7:6] == (v_pgb ? 2'd2 : 2'd1);
wire dsw1_r = io_sel & ~sb_wr & cpu_addr[7:6] == (v_pgb ? 2'd1 : 2'd2);
wire dsw2_r = io_sel & ~sb_wr & cpu_addr[7:6] == (v_pgb ? 2'd0 : 2'd3);
wire sub_w  = io_sel &  sb_wr & cpu_addr[7:6] == 2'd2;          // 5080-50BF (Twin sub latch)
wire pgb_w  = io_sel & sb_wr & v_pgb;
// Birdiy: sound 5080-509F, sprite X/Y 50A0-50AF; Ali Baba: sound 5040-504F + 5060-506F, sprite X/Y 5050-505F
wire bird_w = io_sel & sb_wr & v_bird & cpu_addr[7:6] == 2'd2;
wire wr0_w  = v_pgb  ? pgb_w & cpu_addr[7:4] == 4'h0 : v_bird ? bird_w & cpu_addr[5:4] == 2'd0 :
                                                        grp_w & ~v_bird & cpu_addr[5:4] == 2'd0;   // sound
wire wr1_w  = v_pgb  ? pgb_w & cpu_addr[7:4] == 4'h1 : v_bird ? bird_w & cpu_addr[5:4] == 2'd1 :
              v_alib ? grp_w & cpu_addr[5:4] == 2'd2 : grp_w & cpu_addr[5:4] == 2'd1;   // sound
wire wr2_w  = v_pgb  ? pgb_w & cpu_addr[7:4] == 4'h2 : v_bird ? bird_w & cpu_addr[5:4] == 2'd2 :
              v_alib ? grp_w & cpu_addr[5:4] == 2'd1 : grp_w & cpu_addr[5:4] == 2'd2;   // sprite X/Y

always @(posedge clk) begin
    if (ce6) begin
        if (watchdog_reset | reset) control_reg <= 8'd0;
        else if (out_w)             control_reg[cpu_addr[2:0]] <= cpu_dout[0];
    end
end

// Ali Baba mystery item (MAME alibaba_state): 5080 control, clock steps every 64 frames, 50C0 random, 50C1 clock >= 24
reg  [7:0] mys_ctrl = 8'd0;
reg  [5:0] mys_pre = 6'd0;
reg  [4:0] mys_clock = 5'd0;
reg [15:0] mys_lfsr = 16'hACE1;
wire [3:0] mys_rand = mys_lfsr[3:0];
always @(posedge clk) begin
    mys_lfsr <= {mys_lfsr[14:0], mys_lfsr[15] ^ mys_lfsr[13] ^ mys_lfsr[12] ^ mys_lfsr[10]};
    if (ce6) begin
        if (v_alib && sub_w && cpu_addr[5:0] == 6'd0) begin
            if (mys_ctrl[0] ^ cpu_dout[0]) begin
                mys_pre   <= 6'd0;
                mys_clock <= 5'd0;
            end
            mys_ctrl <= cpu_dout;
        end
        else if (rising_vblank) begin
            mys_pre <= mys_pre + 6'd1;
            if (mys_pre == 6'h3F && mys_ctrl[0]) mys_clock <= mys_clock + 5'd1;
        end
    end
end

// Jr. Pac-Man: latch 2 (5070-5077) banks, playfield scroll (5080)
reg  [7:0] jr_latch2 = 8'd0;
reg  [7:0] jr_scroll = 8'd0;
always @(posedge clk) begin
    if (ce6) begin
        if (watchdog_reset | reset)                         jr_latch2 <= 8'd0;
        else if (v_jr && grp_w && cpu_addr[5:3] == 3'b110) jr_latch2[cpu_addr[2:0]] <= cpu_dout[0];
        if ((v_jr && sub_w && cpu_addr[5:0] == 6'd0) || (v_jrbl && pgb_w && cpu_addr[7:0] == 8'h30)) jr_scroll <= cpu_dout;
    end
end

// Jr. Pac-Man tilemap (MAME jrpacman_scan_rows): 36 x 54, columns 2-33 scroll mod 432 lines, colour per column
wire [5:0] hc      = hcnt[8:3];
wire [5:0] vis_col = (hc >= 6'h1E) ? hc - 6'h1E : hc + 6'd18;
wire [5:0] jr_mc   = (c_flip ? 6'd35 - vis_col : vis_col) - 6'd2;
wire       jr_hud  = jr_mc[5];
wire [7:0] vis_y   = vcnt[7:0] - 8'h10;
wire [7:0] jr_ly   = c_flip ? 8'd223 - vis_y : vis_y;
wire [8:0] py_raw  = {1'b0, jr_ly} + {1'b0, jr_scroll};
wire [8:0] jr_py   = (py_raw >= 9'd432) ? py_raw - 9'd432 : py_raw;
wire [5:0] jr_mr   = jr_hud ? {1'b0, jr_ly[7:3]} + 6'd2 : jr_py[8:3] + 6'd2;
wire [2:0] jr_line = jr_hud ? jr_ly[2:0] : jr_py[2:0];
wire [11:0] jr_code  = ~jr_hud     ? {6'd0, jr_mc} + {1'b0, jr_mr, 5'd0} :
                       jr_mr[5]    ? 12'h77F :
                                     {6'd0, jr_mr} + {1'b0, 4'b1110, jr_mc[1:0], 5'd0};
wire [11:0] jr_color = jr_hud ? jr_code + 12'h080 : {7'd0, jr_mc[4:0]};
wire [11:0] jr_vram  = hcnt[2] ? jr_color : jr_code;

// VRAM address custom: tile columns/rows while 256H, sprite RAM (4FF0) in hblank
wire [4:0] hp = hcnt[7:3] ^ {5{c_flip}};
wire [4:0] vp = vcnt[7:3] ^ {5{c_flip}};

// S2650 boards (MAME s2650_get_tile_info): 32 x 32 in the centre 256H; per-column scroll, tile bank and colour
wire       s26_dbw = ce6 & v_s26 & s26_mem & s26_w & s26_a[12:8] == 5'h14;
reg  [1:0] s26_tbank[32];
reg  [1:0] s26_sbank[8];
always @(posedge clk) begin
    if (s26_dbw && s26_a[7:5] == 3'b101)                s26_tbank[s26_a[4:0]] <= s26_d[1:0];
    if (s26_dbw && s26_a[7:4] == 4'h9 && !s26_a[0])     s26_sbank[s26_a[3:1]] <= s26_d[1:0];
end

wire [7:0] s26_scroll;
dpram_dc #(.widthad_a(5)) s26_scroll_ram
(
    .clock_a(clk),
    .address_a(s26_a[4:0]),
    .data_a(s26_d),
    .wren_a(s26_dbw & s26_a[7:5] == 3'b000),

    .clock_b(clk),
    .address_b(hp),
    .q_b(s26_scroll)
);

wire  [7:0] s26_ty   = (vcnt[7:0] ^ {8{c_flip}}) + s26_scroll;
wire [11:0] s26_vram = hcnt[2] ? {7'b0100000, hp} : {2'b00, s26_ty[7:3], hp};
wire  [1:0] s26_bank = hblank ? s26_sbank[hcnt[6:4]] : s26_tbank[hp];
wire       sel = (hcnt[6:4] == 3'b000) | (hcnt[6:4] == 3'b111);
wire [11:0] y157 = sel ? {1'b0, hcnt[2], hp[3], hp[3], hp[3], hp[3], hp[0], vp[4], vp[3:0]}
                       : {8'hFF, hcnt[6:4], hcnt[2]};
wire [11:0] vram_addr = (jr_tm & ~hblank) ? jr_vram :
                        (v_s26 & ~hblank) ? s26_vram :
                        hcnt[8]     ? {1'b0, hcnt[2], vp, hp} :
                        wide_hblank ? {8'hFF, hcnt[6:4], hcnt[2]} :
                        (v_alib & hblank) ? {8'hEF, hcnt[6:4], hcnt[2]} : y157;      // Ali Baba sprites at 4EF0

wire [11:0] ab = hcnt[1] ? vram_addr : cpu_addr[11:0];
wire  [7:0] ram_data;
wire  [7:0] sb_db = hcnt[1] ? ram_data : cpu_dout;

// 4000-47FF video/colour RAM, 4C00-4FFF work RAM; 4800-4BFF is unpopulated
wire ram_we = ce6 & sb_wr & ~cpu_addr[12] & (ram_48 | ~(cpu_addr[11] & ~cpu_addr[10]));

dpram_dc #(.widthad_a(12)) ram
(
    .clock_a(clk),
    .address_a(ab),
    .data_a(cpu_dout),
    .wren_a(ram_we),
    .q_a(ram_data),

    .clock_b(clk),
    .address_b(hs_address[11:0]),
    .data_b(hs_data_in),
    .wren_b(hs_write),
    .q_b(hs_data_out)
);

// interrupt vector (OUT to any port) and the sync bus read holding register; some bootleg sync bus cards mangle the vector
wire [7:0] vec_in = v_pir   ? (cpu_dout == 8'hFA ? 8'h78 : cpu_dout) :
                    v_mouse ? (cpu_dout == 8'hBF ? 8'h3C : cpu_dout == 8'hC6 ? 8'h40 : cpu_dout) :
                    v_msii  ? (cpu_dout == 8'hFB ? 8'hFE : cpu_dout) : cpu_dout;
reg [7:0] cpu_vec_reg = 8'd0;
reg [7:0] sync_bus_reg = 8'd0;
always @(posedge clk) begin
    if (ce6) begin
        if (~cpu_iorq_n & cpu_m1_n & (~(v_champ | v_pir | v_mouse) | cpu_addr[7:0] == 8'h00)) cpu_vec_reg <= vec_in;
        if (hcnt[1:0] == 2'b01)      sync_bus_reg <= cpu_din;
    end
end
assign s26_dr = s26_io ? s26_io_q : sync_bus_reg;

// Make Trax protection chip (MAME maketrax_protection_w / maketrax_special_port2_r / _port3_r)
reg  [5:0] mt_counter = 6'd0;
reg  [4:0] mt_offset = 5'd0;
reg        mt_disable = 1'b0;
reg        mt_armed = 1'b1;
always @(posedge clk) begin
    if (cpu_mreq_n) mt_armed <= 1'b1;
    if (reset) begin
        mt_counter <= 6'd0;
        mt_offset  <= 5'd0;
        mt_disable <= 1'b0;
    end
    else if (ce6 && v_mt && out_w && cpu_addr[7:0] == 8'h04 && mt_armed) begin
        mt_armed <= 1'b0;
        if (cpu_dout == 8'd0) begin
            mt_counter <= 6'd0;
            mt_offset  <= 5'd0;
            mt_disable <= 1'b1;
        end
        else if (cpu_dout == 8'd1) begin
            mt_disable <= 1'b0;
            if (mt_counter == 6'h3B) begin
                mt_counter <= 6'd0;
                mt_offset  <= (mt_offset == 5'h1D) ? 5'd0 : mt_offset + 5'd1;
            end
            else mt_counter <= mt_counter + 6'd1;
        end
    end
end

reg [7:0] mt_prot2, mt_prot3;
always @(*) begin
    case (mt_offset)
        5'd0 : mt_prot2 = 8'h00;
        5'd1 : mt_prot2 = 8'hC0;
        5'd2 : mt_prot2 = 8'h00;
        5'd3 : mt_prot2 = 8'h40;
        5'd4 : mt_prot2 = 8'hC0;
        5'd5 : mt_prot2 = 8'h40;
        5'd6 : mt_prot2 = 8'h00;
        5'd7 : mt_prot2 = 8'hC0;
        5'd8 : mt_prot2 = 8'h00;
        5'd9 : mt_prot2 = 8'h40;
        5'd10: mt_prot2 = 8'h00;
        5'd11: mt_prot2 = 8'hC0;
        5'd12: mt_prot2 = 8'h00;
        5'd13: mt_prot2 = 8'h40;
        5'd14: mt_prot2 = 8'hC0;
        5'd15: mt_prot2 = 8'h40;
        5'd16: mt_prot2 = 8'h00;
        5'd17: mt_prot2 = 8'hC0;
        5'd18: mt_prot2 = 8'h00;
        5'd19: mt_prot2 = 8'h40;
        5'd20: mt_prot2 = 8'h00;
        5'd21: mt_prot2 = 8'hC0;
        5'd22: mt_prot2 = 8'h00;
        5'd23: mt_prot2 = 8'h40;
        5'd24: mt_prot2 = 8'hC0;
        5'd25: mt_prot2 = 8'h40;
        5'd26: mt_prot2 = 8'h00;
        5'd27: mt_prot2 = 8'hC0;
        5'd28: mt_prot2 = 8'h00;
        5'd29: mt_prot2 = 8'h40;
        default: mt_prot2 = 8'h00;
    endcase
    case (mt_offset)
        5'd0 : mt_prot3 = 8'h1F;
        5'd1 : mt_prot3 = 8'h3F;
        5'd2 : mt_prot3 = 8'h2F;
        5'd3 : mt_prot3 = 8'h2F;
        5'd4 : mt_prot3 = 8'h0F;
        5'd5 : mt_prot3 = 8'h0F;
        5'd6 : mt_prot3 = 8'h0F;
        5'd7 : mt_prot3 = 8'h3F;
        5'd8 : mt_prot3 = 8'h0F;
        5'd9 : mt_prot3 = 8'h0F;
        5'd10: mt_prot3 = 8'h1C;
        5'd11: mt_prot3 = 8'h3C;
        5'd12: mt_prot3 = 8'h2C;
        5'd13: mt_prot3 = 8'h2C;
        5'd14: mt_prot3 = 8'h0C;
        5'd15: mt_prot3 = 8'h0C;
        5'd16: mt_prot3 = 8'h0C;
        5'd17: mt_prot3 = 8'h3C;
        5'd18: mt_prot3 = 8'h0C;
        5'd19: mt_prot3 = 8'h0C;
        5'd20: mt_prot3 = 8'h11;
        5'd21: mt_prot3 = 8'h31;
        5'd22: mt_prot3 = 8'h21;
        5'd23: mt_prot3 = 8'h21;
        5'd24: mt_prot3 = 8'h01;
        5'd25: mt_prot3 = 8'h01;
        5'd26: mt_prot3 = 8'h01;
        5'd27: mt_prot3 = 8'h31;
        5'd28: mt_prot3 = 8'h01;
        5'd29: mt_prot3 = 8'h01;
        default: mt_prot3 = 8'h00;
    endcase
end

wire [7:0] dsw1_lo = {2'b00, dsw1[5:0]};
reg  [7:0] mt_port2, mt_port3, mb_port;
always @(*) begin
    if (!mt_disable) mt_port2 = mt_prot2 | dsw1_lo;
    else case (cpu_addr[5:0])
        6'h01, 6'h04:        mt_port2 = dsw1_lo | 8'h40;
        6'h05, 6'h0E, 6'h10: mt_port2 = dsw1_lo | 8'hC0;
        default:             mt_port2 = dsw1_lo;
    endcase
    if (!mt_disable) mt_port3 = mt_prot3;
    else case (cpu_addr[5:0])
        6'h00:   mt_port3 = 8'h1F;
        6'h09:   mt_port3 = 8'h30;
        6'h0C:   mt_port3 = 8'h00;
        default: mt_port3 = 8'h20;
    endcase
    // Make Trax bootleg (mbrush_prot_r): fixed answers across 5080-50FF
    case (cpu_addr[6:0])
        7'h00, 7'h04, 7'h07, 7'h0E, 7'h0F:         mb_port = dsw1_lo | 8'hC0;
        7'h40, 7'h41, 7'h47, 7'h49, 7'h4D, 7'h5D: mb_port = 8'h00;
        7'h42, 7'h43, 7'h46, 7'h4C, 7'h50:         mb_port = 8'h02;
        7'h7F:                                     mb_port = 8'h10;
        default:                                   mb_port = dsw1_lo;
    endcase
end

//------------------------------------------------------- Program ROM ---------------------------------------------------------//

// Zola-Puc: DSW2 bit 3 picks the 32K program half at reset; port 0 reads DSW2 or the byte last written to port 10/11
reg       champ_bank = 1'b0;
reg       champ_mux = 1'b0;
reg [7:0] champ_mux_data = 8'd0;
// Twin: 5080 write / 50C0 read latch
reg [7:0] twin_sub = 8'd0;
always @(posedge clk) begin
    if (reset) champ_bank <= dsw2[3];
    if (ce6 && ~cpu_iorq_n && cpu_m1_n && ~cpu_wr_n && cpu_addr[7:1] == 7'b0001000) begin
        champ_mux      <= cpu_addr[0];
        champ_mux_data <= cpu_dout;
    end
    if (ce6 && sub_w) twin_sub <= cpu_dout;                 // also Club Pac-Man
end
wire [7:0] ay_dout;
// Super Chick: MAME stubs the protection ports 00/0A/76/78 as FF
wire [7:0] io_data = v_sch   ? ((cpu_addr[7:0] == 8'h00 || cpu_addr[7:0] == 8'h0A || cpu_addr[7:0] == 8'h76 ||
                                 cpu_addr[7:0] == 8'h78) ? 8'hFF : 8'h00) :
                     v_epos  ? 8'h00 :
                     v_crs   ? (cpu_addr[1] ? dsw1 : ay_dout) :
                     champ_mux ? champ_mux_data : {5'd0, dsw2[2:0]};

// Ms. Pac-Man aux board: trap regions switch ROM sets on the same access; 40 patches in 0000-2FFF map to 8000-81EF
reg  ms_dec = 1'b1;
wire [12:0] trap = cpu_addr[15:3];
wire trap_on  = trap == 13'h07FF;
wire trap_off = trap == 13'h0007 || trap == 13'h0076 || trap == 13'h02C0 || trap == 13'h0424 ||
                trap == 13'h07FE || trap == 13'h1000 || trap == 13'h12FE;
wire ms_bank  = trap_on | (ms_dec & ~trap_off);
always @(posedge clk) if (~cpu_mreq_n & cpu_rfsh_n) ms_dec <= ms_bank;

function [13:0] ms_patch(input [12:0] a);
    case (a)
        13'h0082: ms_patch = {1'b1, 13'h1001};
        13'h011C: ms_patch = {1'b1, 13'h103B};
        13'h0146: ms_patch = {1'b1, 13'h1023};
        13'h017A: ms_patch = {1'b1, 13'h101B};
        13'h0184: ms_patch = {1'b1, 13'h1024};
        13'h01CB: ms_patch = {1'b1, 13'h102D};
        13'h01D5: ms_patch = {1'b1, 13'h1033};
        13'h0200: ms_patch = {1'b1, 13'h1004};
        13'h0201: ms_patch = {1'b1, 13'h1002};
        13'h0251: ms_patch = {1'b1, 13'h1013};
        13'h0269: ms_patch = {1'b1, 13'h1009};
        13'h02D1: ms_patch = {1'b1, 13'h1011};
        13'h02D6: ms_patch = {1'b1, 13'h1031};
        13'h02DB: ms_patch = {1'b1, 13'h1019};
        13'h02DF: ms_patch = {1'b1, 13'h1039};
        13'h0335: ms_patch = {1'b1, 13'h1015};
        13'h0337: ms_patch = {1'b1, 13'h1035};
        13'h040C: ms_patch = {1'b1, 13'h1029};
        13'h0421: ms_patch = {1'b1, 13'h1003};
        13'h0434: ms_patch = {1'b1, 13'h1034};
        13'h0453: ms_patch = {1'b1, 13'h1014};
        13'h047C: ms_patch = {1'b1, 13'h101D};
        13'h0483: ms_patch = {1'b1, 13'h1000};
        13'h0489: ms_patch = {1'b1, 13'h100B};
        13'h048E: ms_patch = {1'b1, 13'h1028};
        13'h0491: ms_patch = {1'b1, 13'h1010};
        13'h0496: ms_patch = {1'b1, 13'h1030};
        13'h049B: ms_patch = {1'b1, 13'h1018};
        13'h049F: ms_patch = {1'b1, 13'h1038};
        13'h04E9: ms_patch = {1'b1, 13'h100A};
        13'h04F0: ms_patch = {1'b1, 13'h1012};
        13'h04F7: ms_patch = {1'b1, 13'h1032};
        13'h0500: ms_patch = {1'b1, 13'h1005};
        13'h0564: ms_patch = {1'b1, 13'h1020};
        13'h0566: ms_patch = {1'b1, 13'h1022};
        13'h057E: ms_patch = {1'b1, 13'h103A};
        13'h0598: ms_patch = {1'b1, 13'h101A};
        13'h059B: ms_patch = {1'b1, 13'h101C};
        13'h059E: ms_patch = {1'b1, 13'h103C};
        13'h05AC: ms_patch = {1'b1, 13'h102C};
        default: ms_patch = {1'b0, a};
    endcase
endfunction

wire [13:0] patch = ms_patch(trap);
wire [15:0] ms_a  = patch[13] ? {patch[12:0], cpu_addr[2:0]} : cpu_addr;
wire [11:0] u7_a  = {ms_a[11], ms_a[3], ms_a[7], ms_a[9], ms_a[10], ms_a[8], ms_a[6], ms_a[5], ms_a[4], ms_a[2:0]};
wire [10:0] u5_a  = {ms_a[8], ms_a[7], ms_a[5], ms_a[9], ms_a[10], ms_a[6], ms_a[3], ms_a[4], ms_a[2:0]};
wire [10:0] u6_a  = {ms_a[3], ms_a[7], ms_a[9], ms_a[10], ms_a[8], ms_a[6], ms_a[5], ms_a[4], ms_a[2:0]};

reg [15:0] ms_rom_a;
reg        ms_swap;
always @(*) begin
    ms_swap = 1'b1;
    casez (ms_a[15:11])
        5'b0011?: ms_rom_a = {4'hB, u7_a};                  // 3000-3FFF: u7
        5'b10000: ms_rom_a = {5'b10000, u5_a};              // 8000-87FF: u5
        5'b10001: ms_rom_a = {5'b10011, u6_a};              // 8800-8FFF: u6 high half
        5'b10010: ms_rom_a = {5'b10010, u6_a};              // 9000-97FF: u6 low half
        default: begin
            ms_swap = 1'b0;
            if      (ms_a[15:11] == 5'b10011) ms_rom_a = {5'b00011, ms_a[10:0]};   // 9800-9FFF: Pac-Man 1800-1FFF
            else if (ms_a[15:13] == 3'b101)   ms_rom_a = {3'b001, ms_a[12:0]};    // A000-BFFF: Pac-Man 2000-3FFF
            else                              ms_rom_a = ms_a;
        end
    endcase
end

wire [15:0] rom_base = v_s26   ? {s26_pbank, s26_a[14:0]} :
                       v_sch   ? cpu_addr :
                       v_ms    ? (ms_bank ? ms_rom_a : {2'b00, cpu_addr[13:0]}) :
                       v_champ ? {champ_bank, cpu_addr[15], cpu_addr[13:0]} :
                       v_twin  ? (cpu_addr[14] ? {3'b001, cpu_addr[12:0]} : {cpu_addr[15], 1'b0, cpu_addr[13:0]}) :
                       rom_hi  ? {cpu_addr[15], 1'b0, cpu_addr[13:0]} :
                       (v_pengo | v_pgb) ? {1'b0, cpu_addr[14:0]} :
                       (v_jr | v_rt | v_bb) ? cpu_addr :
                       v_alib  ? (~cpu_addr[15] ? {2'b00, cpu_addr[13:0]} :
                                  cpu_addr[13] ? {5'b10100, cpu_addr[10:0]} : {4'b1000, cpu_addr[11:0]}) :
                                 {2'b00, cpu_addr[13:0]};

// address-wired protection: mspacmbe swaps A0/A1 in 1000-1FFF when A3 is low, mspacmbn inverts the low byte
wire [15:0] rom_addr = (rom_dec == 4'd6 && rom_base[15:12] == 4'h1 && !rom_base[3]) ? {rom_base[15:2], rom_base[0], rom_base[1]} :
                       (rom_dec == 4'd7 && rom_base < 16'hC000) ? {rom_base[15:8], ~rom_base[7:0]} : rom_base;

wire [7:0] rom_raw;
reg  [7:0] rom_data;
dpram_dc #(.widthad_a(16)) prog_rom
(
    .clock_a(clk),
    .address_a(ioctl_addr[15:0]),
    .data_a(ioctl_dout),
    .wren_a(ioctl_wr0 & prog_cs),

    .clock_b(clk),
    .address_b(rom_addr),
    .q_b(rom_raw)
);

wire ram_nop = ~ram_48 & cpu_addr[11:10] == 2'b10;

// Encrypted program ROMs are stored as dumped and decoded on every CPU read (MAME init_eyes, pacplus, jumpshot)
function [7:0] swp(input [7:0] e, input [23:0] s);   // MAME bitswap<8>: s = 8 source bit numbers, MSB first
    for (int i = 0; i < 8; i++) swp[7 - i] = e[s[21 - i*3 +: 3]];
endfunction

wire [4:0]  pick_idx  = {cpu_addr[9], cpu_addr[7], cpu_addr[5], cpu_addr[2], cpu_addr[0]};
localparam [95:0] PICK_PLUS = {3'd2,3'd4,3'd2,3'd4,3'd4,3'd0,3'd4,3'd0,3'd0,3'd4,3'd2,3'd4,3'd0,3'd4,3'd2,3'd2,
                               3'd2,3'd4,3'd0,3'd4,3'd2,3'd2,3'd0,3'd2,3'd2,3'd4,3'd0,3'd4,3'd2,3'd4,3'd2,3'd0};
localparam [95:0] PICK_JMP  = {3'd3,3'd5,3'd3,3'd5,3'd5,3'd1,3'd5,3'd1,3'd3,3'd5,3'd3,3'd5,3'd1,3'd5,3'd3,3'd5,
                               3'd2,3'd0,3'd2,3'd4,3'd4,3'd2,3'd0,3'd2,3'd2,3'd0,3'd2,3'd4,3'd4,3'd4,3'd2,3'd0};
wire [2:0] method = ((rom_dec == 4'd3) ? PICK_JMP[pick_idx*3 +: 3] : PICK_PLUS[pick_idx*3 +: 3]) ^ {2'b00, cpu_addr[11]};

reg [7:0] plus_dec, jmp_dec;
always @(*) begin
    case (method)
        3'd1:    plus_dec = rom_raw ^ 8'h28;
        3'd2:    plus_dec = swp(rom_raw, {3'd6,3'd1,3'd3,3'd2,3'd5,3'd7,3'd0,3'd4}) ^ 8'h96;
        3'd3:    plus_dec = swp(rom_raw, {3'd6,3'd1,3'd5,3'd2,3'd3,3'd7,3'd0,3'd4}) ^ 8'hBE;
        3'd4:    plus_dec = swp(rom_raw, {3'd0,3'd3,3'd7,3'd6,3'd4,3'd2,3'd1,3'd5}) ^ 8'hD5;
        3'd5:    plus_dec = swp(rom_raw, {3'd0,3'd3,3'd4,3'd6,3'd7,3'd2,3'd1,3'd5}) ^ 8'hDD;
        default: plus_dec = rom_raw;
    endcase
    case (method)
        3'd1:    jmp_dec = swp(rom_raw, {3'd7,3'd6,3'd3,3'd4,3'd5,3'd2,3'd1,3'd0}) ^ 8'h20;
        3'd2:    jmp_dec = swp(rom_raw, {3'd5,3'd0,3'd4,3'd3,3'd7,3'd1,3'd2,3'd6}) ^ 8'hA4;
        3'd3:    jmp_dec = swp(rom_raw, {3'd5,3'd0,3'd4,3'd3,3'd7,3'd1,3'd2,3'd6}) ^ 8'h8C;
        3'd4:    jmp_dec = swp(rom_raw, {3'd2,3'd3,3'd1,3'd7,3'd4,3'd6,3'd0,3'd5}) ^ 8'h6E;
        3'd5:    jmp_dec = swp(rom_raw, {3'd2,3'd3,3'd4,3'd7,3'd1,3'd6,3'd0,3'd5}) ^ 8'h4E;
        default: jmp_dec = rom_raw;
    endcase
end

// Super Glob: XOR row from {A12,A8,A4,A0}, column from {D5,D3,D1} (mirrored when D7 is set)
wire [3:0] glob_row = {cpu_addr[12], cpu_addr[8], cpu_addr[4], cpu_addr[0]};
wire [2:0] glob_col = {rom_raw[5], rom_raw[3], rom_raw[1]} ^ {3{rom_raw[7]}};
reg [63:0] glob_xor;   // entry j at [j*8 +: 8]
always @(*) begin
    case (glob_row)
        4'h0, 4'h8:                      glob_xor = 64'hA8A8A8A8A8A8A8A8;
        4'h1, 4'h3, 4'h5, 4'h7:          glob_xor = 64'hA0A088888888A0A0;
        4'h2, 4'hA:                      glob_xor = 64'h8888000088880000;
        4'h4, 4'hC:                      glob_xor = 64'h00002828A0A08888;
        4'h6, 4'hE:                      glob_xor = 64'h8080808020202020;
        default:                         glob_xor = 64'h88880000A0A02828;
    endcase
end
wire [7:0] glob_dec = rom_raw ^ glob_xor[glob_col*8 +: 8];

// Epos: every IN steps a 4-bit counter (odd port down, even port up); counts 8-B pick one of four PAL keys
reg  [3:0] epos_cnt = 4'd0;
reg  [1:0] epos_bank = 2'd0;
reg        epos_armed = 1'b1;
wire [1:0] epos_set = variant[1:0] - 2'd3;                // 11 -> 0, 12 -> 1, 13 -> 2
wire [3:0] epos_step = cpu_addr[0] ? epos_cnt - 4'd1 : epos_cnt + 4'd1;
always @(posedge clk) begin
    if (cpu_iorq_n) epos_armed <= 1'b1;
    if (reset | watchdog_reset) begin
        epos_cnt  <= (epos_set == 2'd0) ? 4'hA : (epos_set == 2'd1) ? 4'hB : 4'h9;
        epos_bank <= (epos_set == 2'd0) ? 2'd2 : (epos_set == 2'd1) ? 2'd3 : 2'd1;
    end
    else if (v_epos && ~cpu_iorq_n && cpu_m1_n && ~cpu_rd_n && epos_armed) begin
        epos_armed <= 1'b0;
        epos_cnt   <= epos_step;
        if (epos_step[3:2] == 2'b10) epos_bank <= epos_step[1:0];
    end
end

reg [7:0] epos_dec;
always @(*) begin
    case ({epos_set, epos_bank})
        4'd0 : epos_dec = swp(rom_raw ^ 8'hFC, {3'd3,3'd7,3'd0,3'd6,3'd4,3'd1,3'd2,3'd5});
        4'd1 : epos_dec = swp(rom_raw ^ 8'hF6, {3'd1,3'd7,3'd0,3'd3,3'd4,3'd6,3'd2,3'd5});
        4'd2 : epos_dec = swp(rom_raw ^ 8'h7D, {3'd3,3'd0,3'd4,3'd6,3'd7,3'd1,3'd2,3'd5});
        4'd3 : epos_dec = swp(rom_raw ^ 8'h77, {3'd1,3'd0,3'd4,3'd3,3'd7,3'd6,3'd2,3'd5});
        4'd4 : epos_dec = swp(rom_raw ^ 8'hB5, {3'd1,3'd6,3'd7,3'd3,3'd4,3'd0,3'd2,3'd5});
        4'd5 : epos_dec = swp(rom_raw ^ 8'hA7, {3'd7,3'd6,3'd1,3'd3,3'd4,3'd0,3'd2,3'd5});
        4'd6 : epos_dec = swp(rom_raw ^ 8'hFC, {3'd1,3'd0,3'd7,3'd6,3'd4,3'd3,3'd2,3'd5});
        4'd7 : epos_dec = swp(rom_raw ^ 8'hEE, {3'd7,3'd0,3'd1,3'd6,3'd4,3'd3,3'd2,3'd5});
        4'd8 : epos_dec = swp(rom_raw ^ 8'hFD, {3'd7,3'd6,3'd1,3'd3,3'd0,3'd4,3'd2,3'd5});
        4'd9 : epos_dec = swp(rom_raw ^ 8'hBF, {3'd7,3'd1,3'd4,3'd3,3'd0,3'd6,3'd2,3'd5});
        4'd10: epos_dec = swp(rom_raw ^ 8'h75, {3'd7,3'd6,3'd1,3'd0,3'd3,3'd4,3'd2,3'd5});
        4'd11: epos_dec = swp(rom_raw ^ 8'h37, {3'd7,3'd1,3'd4,3'd0,3'd3,3'd6,3'd2,3'd5});
        default: epos_dec = rom_raw;
    endcase
end

// Jr. Pac-Man: the encryption PALs XOR bits 0, 2 and 7 by address (MAME init_jrpacman run table, D. Caldwell)
function [7:0] jr_xor(input [15:0] a);
    if      (a <= 16'h00C0) jr_xor = 8'h00;
    else if (a <= 16'h00C2) jr_xor = 8'h80;
    else if (a <= 16'h00C6) jr_xor = 8'h00;
    else if (a <= 16'h00CC) jr_xor = 8'h80;
    else if (a <= 16'h00CF) jr_xor = 8'h00;
    else if (a <= 16'h00D1) jr_xor = 8'h80;
    else if (a <= 16'h00DA) jr_xor = 8'h00;
    else if (a <= 16'h00DE) jr_xor = 8'h80;
    else if (a <= 16'h9A46) jr_xor = 8'h00;
    else if (a <= 16'h9A47) jr_xor = 8'h80;
    else if (a <= 16'h9A49) jr_xor = 8'h00;
    else if (a <= 16'h9A4A) jr_xor = 8'h80;
    else if (a <= 16'h9A53) jr_xor = 8'h00;
    else if (a <= 16'h9A55) jr_xor = 8'h80;
    else if (a <= 16'h9A5E) jr_xor = 8'h00;
    else if (a <= 16'h9A5F) jr_xor = 8'h80;
    else if (a <= 16'h9B0E) jr_xor = 8'h00;
    else if (a <= 16'h9B1C) jr_xor = 8'h04;
    else if (a <= 16'h9B1E) jr_xor = 8'h00;
    else if (a <= 16'h9B22) jr_xor = 8'h04;
    else if (a <= 16'h9B40) jr_xor = 8'h00;
    else if (a <= 16'h9B41) jr_xor = 8'h80;
    else if (a <= 16'h9B43) jr_xor = 8'h00;
    else if (a <= 16'h9B44) jr_xor = 8'h80;
    else if (a <= 16'h9B46) jr_xor = 8'h00;
    else if (a <= 16'h9B48) jr_xor = 8'h80;
    else if (a <= 16'h9B51) jr_xor = 8'h00;
    else if (a <= 16'h9B53) jr_xor = 8'h80;
    else if (a <= 16'h9B5C) jr_xor = 8'h00;
    else if (a <= 16'h9B5E) jr_xor = 8'h80;
    else if (a <= 16'h9BE1) jr_xor = 8'h00;
    else if (a <= 16'h9BE2) jr_xor = 8'h04;
    else if (a <= 16'h9BE3) jr_xor = 8'h01;
    else if (a <= 16'h9BE4) jr_xor = 8'h00;
    else if (a <= 16'h9BE6) jr_xor = 8'h05;
    else if (a <= 16'h9BE7) jr_xor = 8'h00;
    else if (a <= 16'h9BEA) jr_xor = 8'h04;
    else if (a <= 16'h9BED) jr_xor = 8'h01;
    else if (a <= 16'h9BEF) jr_xor = 8'h00;
    else if (a <= 16'h9BF0) jr_xor = 8'h04;
    else if (a <= 16'h9BF3) jr_xor = 8'h01;
    else if (a <= 16'h9BF6) jr_xor = 8'h00;
    else if (a <= 16'h9BF9) jr_xor = 8'h04;
    else if (a <= 16'h9BFA) jr_xor = 8'h01;
    else if (a <= 16'h9C28) jr_xor = 8'h00;
    else if (a <= 16'h9CA0) jr_xor = 8'h01;
    else if (a <= 16'h9CA1) jr_xor = 8'h04;
    else if (a <= 16'h9CA2) jr_xor = 8'h05;
    else if (a <= 16'h9CA3) jr_xor = 8'h00;
    else if (a <= 16'h9CA4) jr_xor = 8'h01;
    else if (a <= 16'h9CA5) jr_xor = 8'h04;
    else if (a <= 16'h9CA7) jr_xor = 8'h00;
    else if (a <= 16'h9CA8) jr_xor = 8'h01;
    else if (a <= 16'h9CA9) jr_xor = 8'h04;
    else if (a <= 16'h9CAB) jr_xor = 8'h00;
    else if (a <= 16'h9CAC) jr_xor = 8'h01;
    else if (a <= 16'h9CAD) jr_xor = 8'h04;
    else if (a <= 16'h9CAF) jr_xor = 8'h00;
    else if (a <= 16'h9CB0) jr_xor = 8'h01;
    else if (a <= 16'h9CB1) jr_xor = 8'h04;
    else if (a <= 16'h9CB2) jr_xor = 8'h05;
    else if (a <= 16'h9CB3) jr_xor = 8'h00;
    else if (a <= 16'h9CB4) jr_xor = 8'h01;
    else if (a <= 16'h9CB5) jr_xor = 8'h04;
    else if (a <= 16'h9CB7) jr_xor = 8'h00;
    else if (a <= 16'h9CB8) jr_xor = 8'h01;
    else if (a <= 16'h9CB9) jr_xor = 8'h04;
    else if (a <= 16'h9CBB) jr_xor = 8'h00;
    else if (a <= 16'h9CBC) jr_xor = 8'h01;
    else if (a <= 16'h9CBD) jr_xor = 8'h04;
    else if (a <= 16'h9CBE) jr_xor = 8'h05;
    else if (a <= 16'h9CBF) jr_xor = 8'h00;
    else if (a <= 16'h9E6F) jr_xor = 8'h01;
    else if (a <= 16'h9E70) jr_xor = 8'h00;
    else if (a <= 16'h9E72) jr_xor = 8'h01;
    else if (a <= 16'h9F1F) jr_xor = 8'h00;
    else if (a <= 16'h9F50) jr_xor = 8'h01;
    else if (a <= 16'h9FAC) jr_xor = 8'h00;
    else if (a <= 16'h9FB1) jr_xor = 8'h01;
    else if (a <= 16'hFFFF) jr_xor = 8'h00;
    else                  jr_xor = 8'h00;
endfunction

// Pengo: Sega 315-5010 / 315-5007 encrypted Z80s (opcode and data halves)
wire [7:0] pengo_5010, pengo_5007;
sega_315_5010 crypt_5010(.src(rom_raw), .addr(cpu_addr), .m1(~cpu_m1_n), .dout(pengo_5010));
sega_315_5007 crypt_5007(.src(rom_raw), .addr(cpu_addr), .m1(~cpu_m1_n), .dout(pengo_5007));

// Super Chick (MAME init_schick): Penta (= 315-5007) below 8000, then an extra layer over the whole ROM
wire [7:0] sch_lo = cpu_addr[8] ? swp(pengo_5007 ^ 8'h41, {3'd7,3'd4,3'd5,3'd6,3'd3,3'd2,3'd1,3'd0})
                                : swp(pengo_5007 ^ 8'h51, {3'd7,3'd6,3'd5,3'd0,3'd3,3'd2,3'd1,3'd4});
wire [7:0] sch_op = cpu_addr[12] ? swp(rom_raw ^ 8'h40, {3'd7,3'd0,3'd5,3'd6,3'd3,3'd2,3'd1,3'd4}) :
                    cpu_addr[8]  ? swp(rom_raw ^ 8'h40, {3'd7,3'd4,3'd5,3'd0,3'd3,3'd2,3'd1,3'd6}) :
                                   swp(rom_raw ^ 8'h41, {3'd7,3'd0,3'd5,3'd6,3'd3,3'd2,3'd1,3'd4});
wire [7:0] sch_dt = cpu_addr[4]  ? swp(rom_raw ^ 8'h11, {3'd7,3'd0,3'd5,3'd6,3'd3,3'd2,3'd1,3'd4})
                                 : swp(rom_raw ^ 8'h51, {3'd7,3'd4,3'd5,3'd0,3'd3,3'd2,3'd1,3'd6});
wire [7:0] sch_dec = ~cpu_addr[15] ? sch_lo : ~cpu_m1_n ? sch_op : sch_dt;

// Super Chick gfx bank bit 1: write 9050 clears, 9060 sets (MAME schick_9050_w / _9060_w, marked as guesses)
reg sch_xbank = 1'b0;
always @(posedge clk) begin
    if (reset) sch_xbank <= 1'b0;
    else if (ce6 && v_sch && pgb_w && cpu_addr[7:0] == 8'h50) sch_xbank <= 1'b0;
    else if (ce6 && v_sch && pgb_w && cpu_addr[7:0] == 8'h60) sch_xbank <= 1'b1;
end

// Twin: opcode fetches and data reads are decoded differently, even and odd bytes each with their own key
wire [7:0] twin_op = cpu_addr[0] ? swp(rom_raw ^ 8'h9A, {3'd6,3'd4,3'd5,3'd7,3'd2,3'd0,3'd3,3'd1})
                                 : swp(rom_raw,         {3'd4,3'd5,3'd6,3'd7,3'd0,3'd1,3'd2,3'd3});
wire [7:0] twin_dt = cpu_addr[0] ? swp(rom_raw ^ 8'hA3, {3'd2,3'd4,3'd6,3'd3,3'd7,3'd0,3'd5,3'd1})
                                 : swp(rom_raw,         {3'd0,3'd1,3'd2,3'd3,3'd4,3'd5,3'd6,3'd7});

always @(*) begin
    case (rom_dec)
        4'd1:    rom_data = swp(rom_raw, {3'd7,3'd6,3'd3,3'd4,3'd5,3'd2,3'd1,3'd0});
        4'd2:    rom_data = plus_dec;
        4'd3:    rom_data = jmp_dec;
        4'd4:    rom_data = glob_dec;
        4'd5:    rom_data = {rom_raw[7:5], rom_raw[3], rom_raw[4], rom_raw[2:0]};
        4'd9:    rom_data = {rom_raw[7], rom_raw[0], rom_raw[5:1], rom_raw[6]};
        4'd10:   rom_data = {rom_raw[7:5], rom_raw[0], rom_raw[3:1], rom_raw[4]};
        default: rom_data = rom_raw;
    endcase
    if (v_ms && ms_bank && ms_swap) rom_data = {rom_raw[0], rom_raw[4], rom_raw[5], rom_raw[7], rom_raw[6], rom_raw[3:1]};
    if (v_twin) rom_data = ~cpu_m1_n ? twin_op : twin_dt;
    if (v_epos) rom_data = epos_dec;
    if (rom_dec == 4'd8) rom_data = {rom_raw[6], rom_raw[7], rom_raw[5:0]};
    if (v_jr) rom_data = rom_raw ^ jr_xor(cpu_addr);
    if (v_rt && cpu_addr == 16'h7FFE) rom_data = 8'hA7;            // MAME init_rocktrv2: bad-dump checksum bytes
    if (v_rt && cpu_addr == 16'h7FEE) rom_data = 8'h6D;
    if (variant == 8'd22) rom_data = pengo_5010;
    if (variant == 8'd23) rom_data = pengo_5007;
    if (v_sch) rom_data = sch_dec;
end


// Cannon Ball: MAME's simulation of the epoxy protection block at 3000-3FFF
reg [15:0] last_m1 = 16'd0;
reg  [2:0] cb_bit = 3'd7;
reg        cb_rst = 1'b0, cb_dec = 1'b0;
wire       cb_rd = v_cball & ~cpu_mreq_n & ~cpu_rd_n & cpu_m1_n & cpu_addr[15:12] == 4'h3;
always @(posedge clk) begin
    if (~cpu_m1_n & ~cpu_mreq_n) last_m1 <= cpu_addr;
    if (cb_rd) begin                                      // apply after the read so the sampled bit holds
        cb_rst <= cpu_addr[11:0] == 12'h004;
        cb_dec <= cpu_addr[11:0] == 12'h001 && last_m1 == 16'h2B97;
    end
    else if (cpu_mreq_n) begin
        if (cb_rst)      cb_bit <= 3'd7;
        else if (cb_dec) cb_bit <= cb_bit - 3'd1;
        cb_rst <= 1'b0;
        cb_dec <= 1'b0;
    end
end
wire [7:0] cb_bits = 8'h46 >> cb_bit;
wire [7:0] cb_prot = cpu_addr[11:0] == 12'h001 ? (last_m1 == 16'h2B97 ? {cb_bits[0], 7'd0} : 8'hFF) :
                     cpu_addr[11:0] == 12'h107 ? 8'h40 : 8'h00;

// Club Pac-Man: IN0/IN1 bits 0-3 are the two joysticks gated by latch Q5 (P1) and Q4 (P2)
wire [3:0] club_joy = (control_reg[5] ? 4'hF : in0[3:0]) & (control_reg[4] ? 4'hF : in1[3:0]);

// SDRAM regions: Rock Tris questions (bank 5FF0), Big Bucks questions (IN, bank 6000), Super ABC program (bank 5002)
reg  [2:0] rt_bank = 3'd0, sabc_bank = 3'd0;
reg  [3:0] bb_bank = 4'd0;
reg  [7:0] rt_prot[4];
wire       mem_rd = ~cpu_mreq_n & cpu_rfsh_n & ~cpu_rd_n;
wire       rt_q   = v_rt & mem_rd & cpu_addr[15];
wire       bb_q   = v_bb & ~cpu_iorq_n & cpu_m1_n & ~cpu_rd_n;
wire       sabc_q = v_sabc & mem_rd & ~cpu_addr[14];
assign sdr_req  = rt_q | bb_q | sabc_q;
assign sdr_addr = rt_q ? {2'b00, rt_bank, cpu_addr[14:0]} :
                  bb_q ? {bb_bank, ~cpu_addr[15:0]} :
                         {1'b0, sabc_bank, ~cpu_addr[15] ? {2'b00, cpu_addr[13:0]} :
                                           cpu_addr[13]  ? cpu_addr : {3'b010, cpu_addr[12:0]}};
wire       rt_io  = v_rt & io_sel & cpu_addr[11:8] == 4'hF;                       // 5Fxx
always @(posedge clk) begin
    if (reset) begin
        rt_bank   <= 3'd0;
        bb_bank   <= 4'd0;
        sabc_bank <= 3'd0;
    end
    else if (ce6) begin
        if (rt_io && sb_wr && cpu_addr[7:2] == 6'b111000) rt_prot[cpu_addr[1:0]] <= cpu_dout;
        if (rt_io && sb_wr && cpu_addr[7:0] == 8'hF0)     rt_bank <= cpu_dout[2:0];
        if (v_bb && ~cpu_mreq_n && ~cpu_wr_n && cpu_addr[15:12] == 4'h6) bb_bank <= cpu_dout[3:0];
        if (v_sabc && out_w && cpu_addr[1:0] == 2'b10)   sabc_bank <= cpu_dout[6:4];
    end
end
wire [7:0] rt_prot_q = rt_prot[cpu_addr[3:2]];
wire [7:0] rt_io_q   = cpu_addr[7:0] == 8'hFF ? dsw2 : {4'd0, rt_prot_q[7:4]};

// Big Bucks: extra 1200 Hz interrupt (MAME set_periodic_int 20 x 60 Hz)
reg [12:0] bb_div = 13'd0;
wire       bb_tick = v_bb & bb_div == 13'd5119;
always @(posedge clk) if (ce6) bb_div <= bb_tick ? 13'd0 : bb_div + 13'd1;

// Pengo on Pac-Man: 4K work RAM at F000
wire [7:0] xram_q;
dpram_dc #(.widthad_a(12)) xram
(
    .clock_a(clk),
    .address_a(v_alib ? {2'b00, cpu_addr[9:0]} : cpu_addr[11:0]),
    .data_a(cpu_dout),
    .wren_a(ce6 & xram_cs & ~cpu_mreq_n & ~cpu_wr_n),
    .q_a(xram_q),
    .clock_b(clk)
);

always @(*) begin
    if (~cpu_iorq_n & ~cpu_m1_n) cpu_din = (v_crs | v_pgb | v_bird | v_bb) ? 8'hFF : cpu_vec_reg;
    else if (~cpu_iorq_n)         cpu_din = v_bb ? sdr_data : io_data;
    else if (rt_q | sabc_q)       cpu_din = sdr_data;
    else if (rt_io & ~sb_wr)      cpu_din = rt_io_q;
    else if (~sb_wait_n)          cpu_din = sync_bus_reg;
    else if (xram_cs)             cpu_din = xram_q;
    else if (rom_cs)              cpu_din = (v_cball && cpu_addr[15:12] == 4'h3) ? cb_prot : rom_data;
    else if (in0_r)               cpu_din = v_club ? {in0[7:4], club_joy} : in0;
    else if (in1_r)               cpu_din = (v_msii && cpu_addr[7:0] >= 8'h4D && cpu_addr[7:0] <= 8'h6F) ?
                                            {in1[7:5], ~cpu_addr[0], in1[3:0]} :           // Ms. Pac-Man II protection
                                  v_club ? {in1[7:4], club_joy} : in1;
    else if (dsw1_r)              cpu_din = v_mt ? mt_port2 : v_mb ? mb_port : v_crs ? in1 : dsw1;
    else if (dsw2_r)              cpu_din = v_mt ? mt_port3 : v_mb ? mb_port : (v_twin | v_club) ? twin_sub :
                                            v_alib ? (cpu_addr[5:0] == 6'd0 ? {4'd0, mys_rand} :
                                                      cpu_addr[5:0] == 6'd1 ? {7'd0, mys_clock >= 5'd24} : 8'hBF) : dsw2;
    else if (v_sch && (cpu_addr[15:13] == 3'b101 || cpu_addr[15:13] == 3'b110))
                                  cpu_din = (cpu_addr == 16'hA808) ? 8'hFF : 8'h00;   // Super Chick: A000-DFFF unmapped
    else if (ram_nop)             cpu_din = 8'hBF;
    else                          cpu_din = ram_data;
end

//--------------------------------------------------------- Video -------------------------------------------------------------//

wire [7:0] rgb;
wire [3:0] sch_pen;

pacman_video video
(
    .clk(clk),
    .ce6(ce6),
    .hcnt(hcnt),
    .vcnt(vcnt),
    .ab(ab),
    .db(sb_db),
    .hblank(hblank),
    .vblank(video_vblank),
    .flip(c_flip),
    .crt_flip(crt_flip ^ v_bird),                           // Birdiy's sprites are mirrored on both axes (MAME inv_spr)
    .out_hblank(video_hblank),
    .ovl_en(v_alib & mys_ctrl[1]),
    .ovl_clock(mys_clock),
    .dl_active(reset),
    .gfx_dec({gfx_dec[3], gfx_dec[1:0]}),
    .spr_xy_we(wr2_w),

    .bankgfx(v_jr | v_pgb),
    .jr(jr_tm | v_s26),
    .pal_nib(jr_tm),
    .sabc(v_sabc),
    .sabc_bank(sabc_bank),
    .jr_charbank(v_jr ? jr_latch2[4] : control_reg[7]),                 // Pengo: Q7 gfx bank; Jr on Pengo: Q7 char bank
    .jr_spritebank(v_jr ? jr_latch2[5] : v_jrbl ? control_reg[5] : control_reg[7]),
    .jr_palbank(v_jr ? jr_latch2[0] : control_reg[2]),
    .jr_colbank(v_jr ? jr_latch2[1] : control_reg[6]),
    .jr_bgpri(v_jr ? jr_latch2[3] : control_reg[4] & ~v_s26 & ~v_sch),
    .jr_line(v_s26 ? s26_ty[2:0] : jr_line),
    .s26(v_s26),
    .s26_bank(s26_bank),
    .sch(v_sch),
    .sch_xbank(sch_xbank),

    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .dl_gfx(ioctl_wr0 & gfx_cs),
    .dl_pal(ioctl_wr0 & pal_cs),
    .dl_lut(ioctl_wr0 & lut_cs),
    .dl_jr_lo(ioctl_wr0 & jr_lo_cs),
    .dl_jr_hi(ioctl_wr0 & jr_hi_cs),
    .dl_clock(ioctl_wr0 & gfx2_cs),
    .dl_sabc(ioctl_wr0 & sabc_gfx_cs),
    .dl_s26(ioctl_wr0 & s26_gfx_cs),
    .dl_sch(ioctl_wr0 & sch_gfx_cs),

    .rgb(rgb),
    .pen(sch_pen)
);

// palette PROM resistor DAC (MAME pacman_palette weights: 1K/470/220, blue 470/220)
function [7:0] dac3(input [2:0] v);
    case (v)
        3'd0: dac3 = 8'd0;   3'd1: dac3 = 8'd33;  3'd2: dac3 = 8'd71;  3'd3: dac3 = 8'd104;
        3'd4: dac3 = 8'd151; 3'd5: dac3 = 8'd184; 3'd6: dac3 = 8'd222; 3'd7: dac3 = 8'd255;
    endcase
endfunction

function [7:0] dac2(input [1:0] v);
    case (v)
        2'd0: dac2 = 8'd0;   2'd1: dac2 = 8'd81;  2'd2: dac2 = 8'd174; 2'd3: dac2 = 8'd255;
    endcase
endfunction

// Super Chick: palette PROMs undumped; MAME's stand-in is R = pen[3:2], G = pen[1:0], B = pen[2:1]
assign video_r = v_sch ? {4{sch_pen[3:2]}} : dac3(rgb[2:0]);
assign video_g = v_sch ? {4{sch_pen[1:0]}} : gfx_dec[2] ? dac2(rgb[7:6]) : dac3(rgb[5:3]);
assign video_b = v_sch ? {4{sch_pen[2:1]}} : gfx_dec[2] ? dac3(rgb[5:3]) : dac2(rgb[7:6]);

//--------------------------------------------------------- Sound -------------------------------------------------------------//

wire signed [15:0] wsg_audio, ay_audio, sch_audio;

// Super Chick sound board, fed by the main CPU's OUT (00)
schick_sound sch_snd
(
    .clk(clk),
    .reset(reset | ~v_sch),
    .pause(pause),
    .vblank(video_vblank),
    .latch_wr(v_sch & ~cpu_iorq_n & cpu_m1_n & ~cpu_wr_n & cpu_addr[7:0] == 8'h00),
    .latch_din(cpu_dout),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .dl_rom(ioctl_wr0 & sch_snd_cs),
    .audio(sch_audio)
);
wire signed [10:0] sn1_snd, sn2_snd;
assign audio = (v_crs | v_dshop) ? ay_audio :
               v_van             ? ($signed({sn1_snd[10], sn1_snd}) + $signed({sn2_snd[10], sn2_snd})) * 16'sd12 :
               v_s26             ? $signed({{5{sn1_snd[10]}}, sn1_snd}) * 16'sd24 :
               v_sch             ? sch_audio :
                                   wsg_audio;

// AY-3-8910 at 1.78975 MHz, data on the even port (MAME data_address_w): Crush Roller 00/01, Dream Shopper 06/07
reg [15:0] ay_acc = 16'd0;
reg        ay_cen = 1'b0;
always @(posedge clk) {ay_cen, ay_acc} <= {1'b0, ay_acc} + 17'd2386;   // 49.152 MHz * 2386 / 65536

reg  ay_armed = 1'b1;
wire sn_io    = v_van & ~cpu_iorq_n & cpu_m1_n & ~cpu_wr_n & ay_armed;
wire ay_io    = ~cpu_iorq_n & cpu_m1_n & ((v_crs & cpu_addr[7:1] == 7'd0) | (v_dshop & cpu_addr[7:1] == 7'd3));
wire ay_wr    = ay_io & ~cpu_wr_n & ay_armed;
always @(posedge clk) begin
    if (cpu_iorq_n)  ay_armed <= 1'b1;
    else if (ay_wr | sn_io) ay_armed <= 1'b0;
end

wire [9:0] ay_sound;
jt49_bus #(.COMP(3'b010)) ay
(
    .rst_n(~reset),
    .clk(clk),
    .clk_en(ay_cen),
    .bdir(ay_wr),
    .bc1(ay_wr ? cpu_addr[0] : 1'b1),
    .din(cpu_dout),
    .sel(1'b1),
    .dout(ay_dout),
    .sound(ay_sound),
    .A(), .B(), .C(),
    .sample(),
    .IOA_in(dsw2),
    .IOA_out(),
    .IOB_in(8'hFF),
    .IOB_out()
);

jt49_dcrm2 #(.sw(16)) ay_dcrm
(
    .clk(clk),
    .cen(ay_cen),
    .rst(reset),
    .din({ay_sound, 6'd0}),
    .dout(ay_audio)
);

// Van-Van: two SN76496 at 1.78975 MHz on ports 01 and 02; S2650 boards: one at 3.072 MHz on the data port
jt89 sn1
(
    .rst(reset),
    .clk(clk),
    .clk_en(v_s26 ? ce6 & hcnt[0] : ay_cen),
    .wr_n(~(v_s26 ? s26_sn_w : sn_io & cpu_addr[7:0] == 8'h01)),
    .cs_n(1'b0),
    .din(cpu_dout),
    .sound(sn1_snd),
    .ready()
);

jt89 sn2
(
    .rst(reset),
    .clk(clk),
    .clk_en(ay_cen),
    .wr_n(~(sn_io & cpu_addr[7:0] == 8'h02)),
    .cs_n(1'b0),
    .din(cpu_dout),
    .sound(sn2_snd),
    .ready()
);

pacman_wsg wsg
(
    .clk(clk),
    .ce6(ce6 & ~pause),
    .hcnt(hcnt),
    .ab(ab[3:0]),
    .db(sb_db[3:0]),
    .wr0(wr0_w),
    .wr1(wr1_w),
    .sound_on(c_sound),

    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .dl_wave(ioctl_wr0 & wave_cs),

    .audio(wsg_audio)
);

endmodule
