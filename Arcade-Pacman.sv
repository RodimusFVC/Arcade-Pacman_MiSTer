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
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [15:0] joystick_0, joystick_1;
wire [15:0] joystick_l_analog_0;   // [15:8] Y, [7:0] X, signed
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
assign AUDIO_S = 1;   // signed
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

///////////////////////////////////////////////////

// MRA index 1:
//   byte 0      board variant (see rtl/pacman_board.sv)
//   byte 1      flags: [0] 4-way joystick, [1] wide hblank (8 sprites, 256 px), [2] coins are 2-frame pulses,
//                      [4] vertical, [7] vertical is ROT90
//   byte 2      CPU ROM decode (see rtl/pacman_board.sv)
//   byte 3      gfx: [0] D4/D6 + A0/A2 swap, [1] Ponpoko order, [2] RBG palette, [3] crush4 split planes
//   byte 4      trackball: [0] X reversed, [1] Y reversed
//   bytes 16-47 input map, one byte per port bit (IN0, IN1, DSW1, DSW2; bit 0 first): control id, 0 = none
// DIP switch bytes 0-3 hold the idle level of every bit of IN0, IN1, DSW1, DSW2; a pressed control inverts its bit
reg [7:0] game_var   = 8'd0;
reg [7:0] game_flags = 8'h91;
reg [3:0] rom_dec    = 4'd0;
reg [3:0] gfx_dec    = 4'd0;
reg [1:0] tb_rev     = 2'd0;
reg       tb_game    = 1'b0;        // input map uses the trackball
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
wire sdram_game = game_var >= 8'd27 && game_var <= 8'd29;   // Rock Tris, Big Bucks, Super ABC
wire vert_view = game_vert & ~status[12];

wire [1:0] ar = status[9:8];

assign VIDEO_ARX = (!ar) ? (vert_view ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (vert_view ? 12'd4 : 12'd3) : 12'd0;

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
	"P2,Game Options;",
	"H1P2O[33:32],Trackball Speed,Normal,Fast,Slow;",
	"H2P2O[36:34],SDRAM Read Latch,Auto,Normal,Early,Late,Later;",
	"-;",
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
	"J1,Btn 1,Btn 2,Btn 3,Btn 4,Coin,Start 1P,Start 2P,Pause,Btn 5,Btn 6,Rack Test;",
	"jn,A,B,X,Y,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

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
	.status_menumask({~sdram_game, ~tb_game, direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),
	.ioctl_wait(sdr_ioctl_wait),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_l_analog_0(joystick_l_analog_0),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse)
);

////////////////////   CLOCKS   ///////////////////

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_49M),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(0),
	.mgmt_address(0),
	.mgmt_writedata(0),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// 6.144 MHz pixel clock enable (18.432 MHz / 3)
reg [2:0] ce_div = 3'd0;
always @(posedge CLK_49M) ce_div <= ce_div + 3'd1;
wire ce6 = (ce_div == 3'd0);

// Hold the Z80 in reset until the PLL is locked and the ROM download has finished
wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked;

///////////////////         Keyboard           //////////////////

reg kb_up = 0, kb_down = 0, kb_left = 0, kb_right = 0;
reg kb_b1 = 0, kb_b2 = 0;
reg kb_coin1 = 0, kb_coin2 = 0, kb_start1 = 0, kb_start2 = 0, kb_pause = 0, kb_service = 0, kb_tilt = 0;

wire       pressed = ~ps2_key[9];
wire [7:0] code    = ps2_key[7:0];

always @(posedge CLK_49M) begin
	reg old_state;
	old_state <= ps2_key[10];
	if (old_state != ps2_key[10]) begin
		case (code)
			'h16: kb_start1  <= pressed; // 1
			'h1E: kb_start2  <= pressed; // 2
			'h2E: kb_coin1   <= pressed; // 5
			'h36: kb_coin2   <= pressed; // 6
			'h46: kb_service <= pressed; // 9
			'h2C: kb_tilt    <= pressed; // T
			'h4D: kb_pause   <= pressed; // P

			'h75: kb_up      <= pressed; // up
			'h72: kb_down    <= pressed; // down
			'h6B: kb_left    <= pressed; // left
			'h74: kb_right   <= pressed; // right
			'h14: kb_b1      <= pressed; // ctrl
			'h11: kb_b2      <= pressed; // alt
		endcase
	end
end

//////////////////  Arcade Buttons/Interfaces   ///////////////////////////

// Joystick bits: 0 R, 1 L, 2 D, 3 U, 4-7 Btn 1-4, 8 Coin, 9 Start 1P, 10 Start 2P, 11 Pause, 12-14 Btn 5-6 + Rack Test (unmapped)
wire [3:0] dir1_raw = {joystick_0[3] | kb_up, joystick_0[2] | kb_down, joystick_0[1] | kb_left, joystick_0[0] | kb_right};
wire [3:0] dir2_raw = joystick_1[3:0];
wire [3:0] dir1, dir2;   // {U, D, L, R}

joy4way joy4way_1(.clk(CLK_49M), .en(game_flags[0]), .in(dir1_raw), .out(dir1));
joy4way joy4way_2(.clk(CLK_49M), .en(game_flags[0]), .in(dir2_raw), .out(dir2));

wire m_pause = joystick_0[11] | kb_pause;

// MAME PORT_IMPULSE(2): a coin press is latched, then held for exactly two frames from the next vblank
wire       coin1_raw = joystick_0[8] | kb_coin1;
wire       coin2_raw = joystick_1[8] | kb_coin2;
reg        coin1_d = 1'b0, coin2_d = 1'b0, coin1_pend = 1'b0, coin2_pend = 1'b0, imp_vbl = 1'b0;
reg  [1:0] coin1_frames = 2'd0, coin2_frames = 2'd0;
always @(posedge CLK_49M) begin
	coin1_d <= coin1_raw;
	coin2_d <= coin2_raw;
	imp_vbl <= vblank;
	if (coin1_raw & ~coin1_d) coin1_pend <= 1'b1;
	if (coin2_raw & ~coin2_d) coin2_pend <= 1'b1;
	if (vblank & ~imp_vbl) begin
		if (coin1_pend)                begin coin1_frames <= 2'd2; coin1_pend <= 1'b0; end
		else if (coin1_frames != 2'd0) coin1_frames <= coin1_frames - 2'd1;
		if (coin2_pend)                begin coin2_frames <= 2'd2; coin2_pend <= 1'b0; end
		else if (coin2_frames != 2'd0) coin2_frames <= coin2_frames - 2'd1;
	end
end
wire coin1 = game_flags[2] ? |coin1_frames : coin1_raw;
wire coin2 = game_flags[2] ? |coin2_frames : coin2_raw;

// Trackball counters from mouse, left stick or d-pad; nibble scaled by Trackball Speed (Normal = MAME's 50%)
reg  [7:0] tb_x = 8'd0, tb_y = 8'd0;
reg        mouse_toggle = 1'b0, tb_vbl = 1'b0;
wire signed [7:0] ana_x = joystick_l_analog_0[7:0];
wire signed [7:0] ana_y = joystick_l_analog_0[15:8];
wire [7:0] tb_dx = (ana_x > 8'sd12 || ana_x < -8'sd12) ? {{4{ana_x[7]}}, ana_x[7:4]} :
                   dir1_raw[0] ? 8'd6 : dir1_raw[1] ? -8'd6 : 8'd0;
wire [7:0] tb_dy = (ana_y > 8'sd12 || ana_y < -8'sd12) ? {{4{ana_y[7]}}, ana_y[7:4]} :
                   dir1_raw[2] ? 8'd6 : dir1_raw[3] ? -8'd6 : 8'd0;
wire [3:0] tb_x_n = status[33] ? tb_x[5:2] : status[32] ? tb_x[3:0] : tb_x[4:1];
wire [3:0] tb_y_n = status[33] ? tb_y[5:2] : status[32] ? tb_y[3:0] : tb_y[4:1];
wire [7:0] mouse_dx = ps2_mouse[15:8];
wire [7:0] mouse_dy = ps2_mouse[23:16];
always @(posedge CLK_49M) begin
	mouse_toggle <= ps2_mouse[24];
	tb_vbl       <= vblank;
	if (mouse_toggle != ps2_mouse[24]) begin
		tb_x <= tb_rev[0] ? tb_x - mouse_dx : tb_x + mouse_dx;
		tb_y <= tb_rev[1] ? tb_y + mouse_dy : tb_y - mouse_dy;           // PS/2 Y is positive upward
	end
	else if (vblank & ~tb_vbl) begin
		tb_x <= tb_rev[0] ? tb_x - tb_dx : tb_x + tb_dx;
		tb_y <= tb_rev[1] ? tb_y - tb_dy : tb_y + tb_dy;
	end
end

// Rack Test cheat: held (MAME DIP with a key), or flipped on each press (MAME PORT_TOGGLE)
wire rack_btn = joystick_0[14] | joystick_1[14];
reg  rack_d = 1'b0, rack_tog = 1'b0;
always @(posedge CLK_49M) begin
	rack_d <= rack_btn;
	if (ioctl_download)        rack_tog <= 1'b0;
	else if (rack_btn & ~rack_d) rack_tog <= ~rack_tog;
end

// control ids used by the MRA input map
wire [63:0] ctl =
{
	26'd0,
	rack_tog,                                       // 37 rack test (toggle)
	rack_btn,                                       // 36 rack test (held)
	joystick_1[13:12],                              // 35-34 P2 Btn 6-5
	joystick_0[13:12],                              // 33-32 P1 Btn 6-5
	tb_y_n,                                         // 31-28 trackball Y counter
	tb_x_n,                                         // 27-24 trackball X counter
	1'b0,                                           // 23 coin 3
	kb_service,                                     // 22 service
	kb_tilt,                                        // 21 tilt
	joystick_0[10] | joystick_1[10] | kb_start2,    // 20 start 2
	joystick_0[9]  | joystick_1[9]  | kb_start1,    // 19 start 1
	coin2,                                          // 18 coin 2
	coin1,                                          // 17 coin 1
	joystick_1[7:4],                                // 16-13 P2 Btn 4-1
	dir2[0], dir2[1], dir2[2], dir2[3],             // 12 R, 11 L, 10 D, 9 U
	joystick_0[7:6], joystick_0[5] | kb_b2, joystick_0[4] | kb_b1,   // 8-5 P1 Btn 4-1
	dir1[0], dir1[1], dir1[2], dir1[3],             // 4 R, 3 L, 2 D, 1 U
	1'b0                                            // 0 none
};

// DIP switches arrive from the OSD via ioctl index 254
reg [7:0] dip_sw[8] = '{8'hFF,8'hFF,8'hFF,8'hFF,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_49M) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

reg [7:0] in_port[4];
always @(posedge CLK_49M) begin
	for (int p = 0; p < 4; p++)
		for (int b = 0; b < 8; b++)
			in_port[p][b] <= dip_sw[p][b] ^ ctl[in_map[p*8 + b]];
end

// PAUSE SYSTEM
wire [23:0] rgb_out;
pause #(8,8,8,49) pause
(
	.*,
	.clk_sys(CLK_49M),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[20:19])
);

///////////////                 Video                  ////////////////

wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix = ce6;

wire rotate_ccw = ~game_flags[7];  // ROT270 sets rotate CCW, ROT90 sets CW
wire no_rotate  = ~game_vert | status[12] | direct_video;
wire flip       = status[11];
screen_rotate screen_rotate(.*);

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

///////////////                 Board                  ////////////////

pacman_board board
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

	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_hs(hs),
	.video_vs(vs),
	.video_hblank(hblank),
	.video_vblank(vblank),

	.audio(audio),

	.hs_address(hs_address),
	.hs_data_in(hs_data_in),
	.hs_data_out(hs_data_out),
	.hs_write(hs_write_enable)
);

// Rock Tris / Big Bucks / Super ABC regions in SDRAM (ioctl index 2); pacman_sdrom codes 0 Early 1 Normal 2 Late 3 Later
wire       rd_auto = (status[36:34] == 3'd0);
wire [1:0] rd_mode = (status[36:34] == 3'd2) ? 2'd0 :
                     (status[36:34] == 3'd3) ? 2'd2 :
                     (status[36:34] == 3'd4) ? 2'd3 : 2'd1;
wire        sdr_req;
wire [19:0] sdr_addr;
wire  [7:0] sdr_data;
wire        sdr_busy;
wire        sdr_ioctl_wait;

pacman_sdrom sdrom
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
	.SDRAM_CLK(SDRAM_CLK)
);

// Hiscore: config = MRA index 3, dump = index 4; RAM via the board's second port while the CPU is paused
wire [15:0] hs_address;
wire  [7:0] hs_data_in;
wire  [7:0] hs_data_out;
wire        hs_write_enable;
wire        hs_access_read;
wire        hs_access_write;
wire        hs_pause;
wire        hs_configured;

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

// 4-way joystick: the most recently pressed direction wins (from the MiSTer Pac-Man port)
module joy4way
(
	input        clk,
	input        en,
	input  [3:0] in,
	output [3:0] out
);

reg  [3:0] mask = 4'hF;
reg  [3:0] in1 = 0, in2 = 0;
wire [3:0] innew = in1 & ~in2;

assign out = in1 & mask;

always @(posedge clk) begin
	in1 <= in;
	in2 <= in1;

	if (innew[0]) mask <= 4'b0001;
	if (innew[1]) mask <= 4'b0010;
	if (innew[2]) mask <= 4'b0100;
	if (innew[3]) mask <= 4'b1000;

	if (!(in & mask) || !en) mask <= 4'hF;
end

endmodule
