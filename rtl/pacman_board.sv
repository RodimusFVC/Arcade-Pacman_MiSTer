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

wire prog_cs, gfx_cs, pal_cs, lut_cs, wave_cs;

selector rom_sel
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(prog_cs),
    .gfx_cs(gfx_cs),
    .pal_cs(pal_cs),
    .lut_cs(lut_cs),
    .wave_cs(wave_cs)
);

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
        else if (hcnt == 9'h08F) hblank <= 1'b1;
        else if (hcnt == 9'h0EF) hblank <= 1'b0;
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
reg   [7:0] cpu_din;
reg         cpu_int_n = 1'b1;
wire        sb_wait_n;

reg   [7:0] control_reg = 8'd0;         // LS259 at 8K: 0 IRQ enable, 1 sound enable, 3 flip, 7 coin counter
reg   [4:0] watchdog = 5'd0;
wire        watchdog_reset = (watchdog == 5'd16);

// T80sed holds MREQ/RD/WR through T2, so every access overlaps the CPU half of the sync bus
T80sed z80
(
    .RESET_n(~(reset | watchdog_reset)),
    .CLK_n(clk),
    .CLKEN(ce6 & hcnt[0] & ~pause),
    .WAIT_n(sb_wait_n),
    .INT_n(cpu_int_n),
    .NMI_n(1'b1),
    .BUSRQ_n(1'b1),
    .M1_n(cpu_m1_n),
    .MREQ_n(cpu_mreq_n),
    .IORQ_n(cpu_iorq_n),
    .RD_n(cpu_rd_n),
    .WR_n(cpu_wr_n),
    .RFSH_n(cpu_rfsh_n),
    .HALT_n(),
    .BUSAK_n(),
    .A(cpu_addr),
    .DI(cpu_din),
    .DO(cpu_dout)
);

wire c_int   = control_reg[0];
wire c_sound = control_reg[1];
wire c_flip  = control_reg[3] ^ crt_flip;

// vblank IRQ held until the game clears the enable latch; watchdog = 16 frames
always @(posedge clk) begin
    if (ce6) begin
        if (!c_int)             cpu_int_n <= 1'b1;
        else if (rising_vblank) cpu_int_n <= 1'b0;

        if (reset | wdr_w | pause) watchdog <= 5'd0;
        else if (rising_vblank)    watchdog <= watchdog_reset ? 5'd0 : watchdog + 5'd1;
    end
end

//------------------------------------------------------- Sync bus ------------------------------------------------------------//

// 4000-7FFF (A15 unused): CPU owns the bus while 2H is low, video while 2H is high; reads wait out the video half
wire sb_cs  = ~cpu_mreq_n & cpu_rfsh_n & cpu_addr[14];
wire sb_stb = sb_cs & ~hcnt[1];
wire sb_wr  = sb_stb & cpu_rd_n;
assign sb_wait_n = ~(sb_cs & hcnt[1] & ~cpu_rd_n);

wire io_sel = sb_stb & cpu_addr[12];
wire out_w  = io_sel &  sb_wr & cpu_addr[7:6] == 2'd0;          // 5000-503F latch
wire grp_w  = io_sel &  sb_wr & cpu_addr[7:6] == 2'd1;          // 5040-507F
wire wdr_w  = io_sel &  sb_wr & cpu_addr[7:6] == 2'd3;          // 50C0-50FF watchdog
wire in0_r  = io_sel & ~sb_wr & cpu_addr[7:6] == 2'd0;
wire in1_r  = io_sel & ~sb_wr & cpu_addr[7:6] == 2'd1;
wire dsw1_r = io_sel & ~sb_wr & cpu_addr[7:6] == 2'd2;
wire dsw2_r = io_sel & ~sb_wr & cpu_addr[7:6] == 2'd3;
wire wr0_w  = grp_w & cpu_addr[5:4] == 2'd0;                    // 5040-504F sound
wire wr1_w  = grp_w & cpu_addr[5:4] == 2'd1;                    // 5050-505F sound
wire wr2_w  = grp_w & cpu_addr[5:4] == 2'd2;                    // 5060-506F sprite X/Y

always @(posedge clk) begin
    if (ce6) begin
        if (watchdog_reset | reset) control_reg <= 8'd0;
        else if (out_w)             control_reg[cpu_addr[2:0]] <= cpu_dout[0];
    end
end

// VRAM address custom: tile columns/rows while 256H, sprite RAM (4FF0) in hblank
wire [4:0] hp = hcnt[7:3] ^ {5{c_flip}};
wire [4:0] vp = vcnt[7:3] ^ {5{c_flip}};
wire       sel = (hcnt[6:4] == 3'b000) | (hcnt[6:4] == 3'b111);
wire [11:0] y157 = sel ? {1'b0, hcnt[2], hp[3], hp[3], hp[3], hp[3], hp[0], vp[4], vp[3:0]}
                       : {8'hFF, hcnt[6:4], hcnt[2]};
wire [11:0] vram_addr = hcnt[8] ? {1'b0, hcnt[2], vp, hp} : y157;

wire [11:0] ab = hcnt[1] ? vram_addr : cpu_addr[11:0];
wire  [7:0] ram_data;
wire  [7:0] sb_db = hcnt[1] ? ram_data : cpu_dout;

// 4000-47FF video/colour RAM, 4C00-4FFF work RAM; 4800-4BFF is unpopulated
wire ram_we = ce6 & sb_wr & ~cpu_addr[12] & ~(cpu_addr[11] & ~cpu_addr[10]);

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

// interrupt vector (OUT to any port) and the sync bus read holding register
reg [7:0] cpu_vec_reg = 8'd0;
reg [7:0] sync_bus_reg = 8'd0;
always @(posedge clk) begin
    if (ce6) begin
        if (~cpu_iorq_n & cpu_m1_n)  cpu_vec_reg  <= cpu_dout;
        if (hcnt[1:0] == 2'b01)      sync_bus_reg <= cpu_din;
    end
end

//------------------------------------------------------- Program ROM ---------------------------------------------------------//

wire [7:0] rom_data;
dpram_dc #(.widthad_a(16)) prog_rom
(
    .clock_a(clk),
    .address_a(ioctl_addr[15:0]),
    .data_a(ioctl_dout),
    .wren_a(ioctl_wr0 & prog_cs),

    .clock_b(clk),
    .address_b({2'b00, cpu_addr[13:0]}),
    .q_b(rom_data)
);

wire ram_nop = cpu_addr[11:10] == 2'b10;

always @(*) begin
    if (~cpu_iorq_n & ~cpu_m1_n) cpu_din = cpu_vec_reg;
    else if (~sb_wait_n)          cpu_din = sync_bus_reg;
    else if (~cpu_addr[14])       cpu_din = rom_data;
    else if (in0_r)               cpu_din = in0;
    else if (in1_r)               cpu_din = in1;
    else if (dsw1_r)              cpu_din = dsw1;
    else if (dsw2_r)              cpu_din = dsw2;
    else if (ram_nop)             cpu_din = 8'hBF;
    else                          cpu_din = ram_data;
end

//--------------------------------------------------------- Video -------------------------------------------------------------//

wire [7:0] rgb;

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
    .crt_flip(crt_flip),
    .spr_xy_we(wr2_w),

    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .dl_gfx(ioctl_wr0 & gfx_cs),
    .dl_pal(ioctl_wr0 & pal_cs),
    .dl_lut(ioctl_wr0 & lut_cs),

    .rgb(rgb)
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

assign video_r = dac3(rgb[2:0]);
assign video_g = dac3(rgb[5:3]);
assign video_b = dac2(rgb[7:6]);

//--------------------------------------------------------- Sound -------------------------------------------------------------//

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

    .audio(audio)
);

endmodule
