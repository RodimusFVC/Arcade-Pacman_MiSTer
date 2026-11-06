//============================================================================
//
//  Pac-Man hardware for MiSTer
//  Copyright (C) 2026 Rodimus
//
//  Board model derived from "A simulation model of Pacman hardware" by
//  MikeJ (fpgaarcade.com) and the MiSTer Pac-Man port by Sorgelig
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

wire        CLK_49M;
wire        locked;
wire [127:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;
wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_din;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
wire [26:0] ioctl_addr27;
wire [24:0] ioctl_addr = ioctl_addr27[24:0];
wire  [7:0] ioctl_dout;
wire [15:0] joystick_0, joystick_1;
wire [15:0] joystick_l_analog_0;
wire [21:0] gamma_bus;
wire        direct_video;
wire        video_rotated;
wire        pause_cpu;
wire        hblank, vblank;

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire signed [15:0] audio;
assign AUDIO_L = pause_cpu ? 16'd0 : audio;
assign AUDIO_R = pause_cpu ? 16'd0 : audio;
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

// MRA index 1:
//   byte 0      board variant (see rtl/boards/pacman/pacman_board.sv)
//   byte 1      flags: [0] 4-way joystick, [1] wide hblank (8 sprites, 256 px), [2] coins are 2-frame pulses,
//                      [4] vertical, [7] vertical is ROT90
//   byte 2      CPU ROM decode (see rtl/boards/pacman/pacman_board.sv)
//   byte 3      gfx: [0] D4/D6 + A0/A2 swap, [1] Ponpoko order, [2] RBG palette, [3] crush4 split planes
//   byte 4      trackball: [0] X reversed, [1] Y reversed
//   bytes 16-47 input map, one byte per port bit (IN0, IN1, DSW1, DSW2; bit 0 first): control id, 0 = none
// DIP switch bytes 0-3 hold the idle level of every bit of IN0, IN1, DSW1, DSW2; a pressed control inverts its bit
reg [7:0] game_var   = 8'd0;
reg [7:0] game_flags = 8'h91;
reg [3:0] rom_dec    = 4'd0;
reg [3:0] gfx_dec    = 4'd0;
reg [1:0] tb_rev     = 2'd0;
reg       tb_game    = 1'b0;
reg [5:0] in_map[32];

always @(posedge CLK_49M) begin
    if (ioctl_wr && ioctl_index == 8'd1) begin
        if (ioctl_addr == 25'd0) begin game_var <= ioctl_dout; tb_game <= 1'b0; end
        if (ioctl_addr >= 25'd16 && ioctl_dout >= 8'd24 && ioctl_dout < 8'd32) tb_game <= 1'b1;
        if (ioctl_addr == 25'd1) game_flags <= ioctl_dout;
        if (ioctl_addr == 25'd2) rom_dec    <= ioctl_dout[3:0];
        if (ioctl_addr == 25'd3) gfx_dec    <= ioctl_dout[3:0];
        if (ioctl_addr == 25'd4) tb_rev     <= ioctl_dout[1:0];
        if (ioctl_addr[24:5] == 20'd0 && ioctl_addr[4]) in_map[{1'b0, ioctl_addr[3:0]}] <= ioctl_dout[5:0];
        if (ioctl_addr[24:5] == 20'd1 && ioctl_addr[4] == 1'b0) in_map[{1'b1, ioctl_addr[3:0]}] <= ioctl_dout[5:0];
    end
end

wire game_vert  = game_flags[4];
wire sdram_game = game_var >= 8'd27 && game_var <= 8'd29;
wire vert_view = game_vert & ~status[12];

wire [1:0] ar = status[9:8];

wire        art_fb;
wire        art_wait, art_avail;
wire [11:0] art_cw, art_ch;
assign VIDEO_ARX = (!ar) ? (art_fb ? art_cw : vert_view ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (art_fb ? art_ch : vert_view ? 12'd4 : 12'd3) : 12'd0;

// Status bits avoid the old Pac-Man core's 2-7, 14-15 and 23-31 so its saved settings can't leak in
`include "build_id.v"
localparam CONF_STR = {
	"PACMAN;;",
	"P1,Video Options;",
	"P1O89,Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"P1OC,Orientation,Vert,Horz;",
	"P1OB,HDMI Flip,Off,On;",
	"P1OM,CRT Flip,Off,On;",
	"P1O[40:37],H Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[44:41],V Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1OGI,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"H4P2,Game Options;",
	"H1P2O[33:32],Trackball Speed,Normal,Fast,Slow;",
	"H2P2O[36:34],SDRAM Read Latch,Auto,Normal,Early,Late,Later;",
	"H2P2O[48:45],SDRAM Clk Phase,Auto,0.0ns,1.4ns,2.8ns,4.2ns,5.7ns,7.1ns,8.5ns,9.9ns,11.3ns,12.7ns,14.1ns,15.5ns,17.0ns,18.4ns,19.8ns;",
	"H3P2-;",
	"H3P2-,Artwork (MAME layout views);",
	"H3P2O[52:49],View,Off,View 1,View 2,View 3,View 4,View 5,View 6,View 7,View 8,View 9,View 10,View 11,View 12,View 13,View 14,View 15;",
	"H3P2O[53],Backdrop,On,Off;",
	"H3P2O[54],Overlay,On,Off;",
	"H3P2O[55],Bezel,On,Off;",
	"H3P2O[58],Control Panel,On,Off;",
	"H3P2O[56],Side Art,On,Off;",
	"H3P2O[57],Zoom to Screen,Off,On;",
	"H4-;",
	"P3,Pause Options;",
	"P3OJ,Pause when OSD is open,On,Off;",
	"P3OK,Dim video after 10s,On,Off;",
	"-;",
	"P4,High Score Options;",
	"P4OL,Autosave Hiscores,Off,On;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Button 1,Button 2,Button 3,Button 4,Coin,Start 1P,Start 2P,Pause,Button 5,Button 6,Rack Test;",
	"jn,A,B,X,Y,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

wire        sdr_req;
wire [19:0] sdr_addr;
wire  [7:0] sdr_data;
wire        sdr_busy;
wire        sdr_ioctl_wait;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_49M),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({~(art_avail | sdram_game | tb_game), ~art_avail, ~sdram_game, ~tb_game, direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),
	.ioctl_wait(sdr_ioctl_wait | art_wait),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_l_analog_0(joystick_l_analog_0),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        CLK_SDRAM;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_49M),
	.outclk_1(CLK_SDRAM),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

wire        cfg_waitrequest;
wire        cfg_write;
wire  [5:0] cfg_address;
wire [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

wire       ph_auto = (status[48:45] == 4'd0);
wire [6:0] cal_ph;
wire       cal_tgl, cal_hold, ph_ack_tgl;

sdram_phase_ctl #(.CNT_SEL(5'd1), .MAN_STEP(7'd5)) phase_ctl
(
	.clk(CLK_50M),
	.sel(status[48:45]),
	.cal_val(cal_ph),
	.cal_tgl(cal_tgl),
	.ack_tgl(ph_ack_tgl),
	.cfg_waitrequest(cfg_waitrequest),
	.cfg_write(cfg_write),
	.cfg_address(cfg_address),
	.cfg_data(cfg_data)
);

reg  [2:0] ph_ack_s = 3'd0;
always @(posedge CLK_49M) ph_ack_s <= {ph_ack_s[1:0], ph_ack_tgl};
wire       sdr_recal = ph_ack_s[2] ^ ph_ack_s[1];

reg [2:0] ce_div = 3'd0;
always @(posedge CLK_49M) ce_div <= ce_div + 3'd1;
wire ce6 = (ce_div == 3'd0);

wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked | cal_hold;

wire [12:0] kb;
/* verilator lint_off PINCONNECTEMPTY */
ctl_keyboard u_kb(.clk(CLK_49M), .ps2_key(ps2_key), .pause(pause_cpu), .kb(kb), .kbx());
/* verilator lint_on PINCONNECTEMPTY */

wire [3:0] dir1_raw = {joystick_0[3] | kb[0], joystick_0[2] | kb[1], joystick_0[1] | kb[2], joystick_0[0] | kb[3]};
wire [3:0] dir2_raw = joystick_1[3:0];
wire [3:0] dir1, dir2;

ctl_joy4way u_j4w1(.clk(CLK_49M), .en(game_flags[0]), .in(dir1_raw), .out(dir1));
ctl_joy4way u_j4w2(.clk(CLK_49M), .en(game_flags[0]), .in(dir2_raw), .out(dir2));

wire m_pause = joystick_0[11] | kb[12];

wire coin1, coin2;
ctl_coin_impulse #(.FRAMES(4'd2), .PAUSE_MODE(1)) u_coin1(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                                          .coin_raw(joystick_0[8] | kb[8]), .coin(coin1));
ctl_coin_impulse #(.FRAMES(4'd2), .PAUSE_MODE(1)) u_coin2(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                                          .coin_raw(joystick_1[8] | kb[9]), .coin(coin2));

wire       ms_ev;
wire [9:0] ms_dx, ms_dy;
/* verilator lint_off UNUSED */
wire [2:0] ms_btn;
wire [1:0] tb_dir;
/* verilator lint_on UNUSED */
wire [3:0] tb_x_n, tb_y_n;
wire       tb_tick;
ctl_mouse u_ms(.clk(CLK_49M), .ps2_mouse(ps2_mouse), .ev(ms_ev), .dx(ms_dx), .dy(ms_dy), .btn(ms_btn));
ctl_tick #(.MODE(0)) u_tbt(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .period(18'd0), .tick(tb_tick));
ctl_trackball #(.CW(8), .OUT_W(4), .STICK_RSH(4), .DPAD_STEP(6), .DZ(12)) u_tb
(
	.clk(CLK_49M), .reset(1'b0), .pause(pause_cpu), .rev(tb_rev), .unit_sh(2'd0), .base_sh(4'd1),
	.speed(status[33] ? 2'd2 : status[32] ? 2'd1 : 2'd0),
	.mouse_ev(ms_ev), .mouse_dx(ms_dx), .mouse_dy(ms_dy), .spinner(9'd0), .quad_ce(2'b00), .quad_dir(2'b00),
	.tick(tb_tick), .stick_en(1'b1), .stick(joystick_l_analog_0), .dpad(dir1_raw), .x(tb_x_n), .y(tb_y_n), .dir(tb_dir)
);

wire rack_btn = joystick_0[14] | joystick_1[14];
wire rack_tog;
ctl_toggle u_rack(.clk(CLK_49M), .clear(ioctl_download), .btn(rack_btn), .pause(pause_cpu), .q(rack_tog));

/* verilator lint_off UNUSED */
wire [35:0] ids;
/* verilator lint_on UNUSED */
ctl_ids u_ids
(
	.joy0(joystick_0), .joy1(joystick_1), .kb(kb), .dir1(dir1), .dir2(dir2),
	.coin1(coin1), .coin2(coin2), .coin3(1'b0), .ctl(ids)
);
wire [63:0] ctl =
{
	26'd0,
	rack_tog,
	rack_btn,
	ids[35:32],
	tb_y_n,
	tb_x_n,
	ids[23:0]
};

reg [7:0] dip_sw[8] = '{8'hFF,8'hFF,8'hFF,8'hFF,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_49M) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

wire [255:0] in_map_flat;
genvar mi;
generate
	for (mi = 0; mi < 32; mi = mi + 1) begin : g_map
		assign in_map_flat[mi*8 +: 8] = {2'b00, in_map[mi]};
	end
endgenerate
wire [31:0] ports;
ctl_port_map #(.NP(4), .IDW(6), .DIP_MODE(0)) u_ports
(
	.clk(CLK_49M), .idle({dip_sw[3], dip_sw[2], dip_sw[1], dip_sw[0]}), .in_map(in_map_flat), .dips(32'd0),
	.port_sel(32'd0), .dip_bytes(64'd0), .dip_bit(96'd0),
	.ctl(ctl), .ovr_mask(32'd0), .ovr_val(32'd0), .ports(ports)
);
wire [7:0] in_port[4];
genvar pi;
generate
	for (pi = 0; pi < 4; pi = pi + 1) begin : g_port
		assign in_port[pi] = ports[pi*8 +: 8];
	end
endgenerate

wire [15:0] hs_address;
wire  [7:0] hs_data_in;
wire  [7:0] hs_data_out;
wire        hs_write_enable;
wire        hs_access_read;
wire        hs_access_write;
wire        hs_pause;
wire        hs_configured;

wire [23:0] rgb_out;
pause #(8,8,8,49) pause
(
	.*,
	.clk_sys(CLK_49M),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[20:19])
);

wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix = ce6;
wire        bd_hs, bd_vs, bd_hbl, bd_vbl;
wire  [7:0] bd_r, bd_g, bd_b;

wire        art_run, art_ddr;
wire [31:0] art_fb_base;
wire  [7:0] art_burstcnt, art_be;
wire [28:0] art_addr;
wire [63:0] art_din;
wire        art_rd, art_we, art_clk;
artwork #(.IDX(8'd5)) artwork
(
	.clk(CLK_49M),
	.sel(status[52:49]), .layer_off({status[58], status[55:53]}), .side_off(status[56]), .zoom(status[57]),
	.crt_flip(status[22]), .hdmi_flip(status[11]), .turn(status[12]), .avail(art_avail),
	.hdmi_w(HDMI_WIDTH), .hdmi_h(HDMI_HEIGHT),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27), .ioctl_dout(ioctl_dout), .ioctl_wait(art_wait),
	.ce_pix(ce_pix),
	.hs_in(bd_hs), .vs_in(bd_vs), .hblank_in(bd_hbl), .vblank_in(bd_vbl), .rgb_in({bd_r, bd_g, bd_b}),
	.hs_out(hs), .vs_out(vs), .hblank_out(hblank), .vblank_out(vblank), .rgb_out({r, g, b}),
	.running(art_run), .ddr_owner(art_ddr), .canvas_w(art_cw), .canvas_h(art_ch),
	.fb_base(art_fb_base), .fb_vbl(FB_VBL),
	.DDRAM_CLK(art_clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(art_burstcnt), .DDRAM_ADDR(art_addr),
	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(art_rd),
	.DDRAM_DIN(art_din), .DDRAM_BE(art_be), .DDRAM_WE(art_we)
);
assign art_fb = art_run & ~direct_video;

wire rotate_ccw = ~game_flags[7];
wire no_rotate  = ~game_vert | status[12] | direct_video;
wire flip       = status[11];
wire        sr_fb_en, sr_clk, sr_rd, sr_we;
wire  [4:0] sr_fb_format;
wire [11:0] sr_fb_w, sr_fb_h;
wire [31:0] sr_fb_base;
wire [13:0] sr_fb_stride;
wire  [7:0] sr_burstcnt, sr_be;
wire [28:0] sr_addr;
wire [63:0] sr_din;
screen_rotate screen_rotate
(
	.*,
	.FB_EN(sr_fb_en), .FB_FORMAT(sr_fb_format), .FB_WIDTH(sr_fb_w), .FB_HEIGHT(sr_fb_h),
	.FB_BASE(sr_fb_base), .FB_STRIDE(sr_fb_stride),
	.DDRAM_CLK(sr_clk), .DDRAM_BURSTCNT(sr_burstcnt), .DDRAM_ADDR(sr_addr), .DDRAM_DIN(sr_din),
	.DDRAM_BE(sr_be), .DDRAM_WE(sr_we), .DDRAM_RD(sr_rd)
);

assign FB_EN     = art_fb | sr_fb_en;
assign FB_FORMAT = art_fb ? 5'b00110  : sr_fb_format;
assign FB_WIDTH  = art_fb ? art_cw    : sr_fb_w;
assign FB_HEIGHT = art_fb ? art_ch    : sr_fb_h;
assign FB_BASE   = art_fb ? art_fb_base : sr_fb_base;
assign FB_STRIDE = art_fb ? 14'd8192  : sr_fb_stride;
assign DDRAM_CLK      = CLK_49M;
assign DDRAM_BURSTCNT = art_ddr ? art_burstcnt : sr_burstcnt;
assign DDRAM_ADDR     = art_ddr ? art_addr : sr_addr;
assign DDRAM_DIN      = art_ddr ? art_din : sr_din;
assign DDRAM_BE       = art_ddr ? art_be : sr_be;
assign DDRAM_WE       = art_ddr ? art_we : sr_we;
assign DDRAM_RD       = art_ddr ? art_rd : sr_rd;

arcade_video #(288,24) arcade_video
(
	.*,

	.clk_video(CLK_49M),

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[18:16])
);

pacman_dispatcher board
(
	.clk(CLK_49M),
	.reset(reset),
	.ce6(ce6),
	.pause(pause_cpu),
	.variant(game_var),
	.sdr_req(sdr_req),
	.sdr_addr(sdr_addr),
	.sdr_data(sdr_data),
	.sdr_busy(sdr_busy),
	.wide_hblank(game_flags[1]),
	.rom_dec(rom_dec),
	.gfx_dec(gfx_dec),

	.in0(in_port[0]),
	.in1(in_port[1]),
	.dsw1(in_port[2]),
	.dsw2(in_port[3]),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr0(ioctl_wr & (ioctl_index == 8'd0)),

	.crt_flip(status[22]),
	.h_adj(status[40:37]),
	.v_adj(status[44:41]),

	.video_r(bd_r),
	.video_g(bd_g),
	.video_b(bd_b),
	.video_hs(bd_hs),
	.video_vs(bd_vs),
	.video_hblank(bd_hbl),
	.video_vblank(bd_vbl),

	.audio(audio),

	.hs_address(hs_address),
	.hs_data_in(hs_data_in),
	.hs_data_out(hs_data_out),
	.hs_write(hs_write_enable)
);

wire       rd_auto = (status[36:34] == 3'd0);
wire [1:0] rd_mode = (status[36:34] == 3'd2) ? 2'd0 :
                     (status[36:34] == 3'd3) ? 2'd2 :
                     (status[36:34] == 3'd4) ? 2'd3 : 2'd1;

sdram_rom sdrom
(
	.clk(CLK_49M),
	.por_reset(~locked),

	.ioctl_download(ioctl_download),
	.ioctl_wr2(ioctl_wr & (ioctl_index == 8'd2)),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(sdr_ioctl_wait),

	.rd_auto(rd_auto),
	.rd_mode(rd_mode),
	.cpu_req(sdr_req),
	.cpu_addr(sdr_addr),
	.cpu_data(sdr_data),
	.cpu_busy(sdr_busy),

	.recal(sdr_recal),
	.ph_auto(ph_auto),
	.ld_hold(status[0]),
	.ph_req_val(cal_ph),
	.ph_req_tgl(cal_tgl),
	.cal_hold(cal_hold),

	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_A(SDRAM_A),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_CLK()
);

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(CLK_SDRAM),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);


hiscore #(
	.HS_ADDRESSWIDTH(16),
	.CFG_ADDRESSWIDTH(4),
	.CFG_LENGTHWIDTH(2)
) hi (
	.*,
	.clk(CLK_49M),
	.paused(pause_cpu),
	.autosave(status[21]),
	.ram_address(hs_address),
	.data_from_ram(hs_data_out),
	.data_to_ram(hs_data_in),
	.data_from_hps(ioctl_dout),
	.data_to_hps(ioctl_din),
	.ram_write(hs_write_enable),
	.ram_intent_read(hs_access_read),
	.ram_intent_write(hs_access_write),
	.pause_cpu(hs_pause),
	.configured(hs_configured)
);

endmodule
