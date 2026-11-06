// From "A simulation model of Pacman hardware"
//  Copyright (c) MikeJ - January 2006 (www.fpgaarcade.com), BSD licence;
//  MiSTer merge by Alexey Melnikov (Sorgelig)

module pacman_video
(
    input               clk,
    input               ce6,

    input         [8:0] hcnt,
    input         [8:0] vcnt,
    input        [11:0] ab,
    input         [7:0] db,
    input               hblank,
    input               vblank,
    input               flip,
    input               crt_flip,
    input         [2:0] gfx_dec,        // [0] D4/D6 and A0/A2 swapped, [1] Ponpoko byte order, [2] crush4 split planes
    input               dl_active,
    input               out_hblank,
    input               ovl_en,
    input         [4:0] ovl_clock,
    input               spr_xy_we,

    input               bankgfx,
    input               jr,
    input               pal_nib,
    input               sabc,
    input         [2:0] sabc_bank,
    input               jr_charbank,
    input               jr_spritebank,
    input               jr_palbank,
    input               jr_colbank,
    input               jr_bgpri,
    input         [2:0] jr_line,
    input               s26,
    input         [1:0] s26_bank,
    input               sch,
    input               sch_xbank,

    input        [24:0] ioctl_addr,
    input               dl_sabc,
    input               dl_s26,
    input               dl_sch,

    output       [15:0] gfx_a_a,
    input         [7:0] gfx_a_q,
    output       [15:0] gfx_b_a,
    input         [7:0] gfx_b_q,
    output        [7:0] lut_a_a,
    input         [7:0] lut_a_q,
    output        [7:0] lut_b_a,
    input         [7:0] lut_b_q,
    output       [10:0] clk_a_a,
    input         [7:0] clk_a_q,
    output       [10:0] clk_b_a,
    input         [7:0] clk_b_q,
    output        [4:0] pal_a,
    input         [7:0] pal_q,
    output        [4:0] jrpal_a,
    input         [7:0] jrlo_q,
    input         [7:0] jrhi_q,
    output ram_pool_pkg::pram_i_t [1:0] pr_i,
    input  ram_pool_pkg::pram_o_t [1:0] pr_o,

    output        [7:0] rgb,            // palette PROM byte: B[7:6] G[5:3] R[2:0]
    output        [3:0] pen
);

wire [7:0] xy_raw;
assign pr_i[1].a_addr = {12'd0, ab[3:0]};
assign pr_i[1].a_d    = db;
assign pr_i[1].a_we   = ce6 & spr_xy_we;
assign pr_i[1].b_addr = {12'd0, ab[3:0]};
assign pr_i[1].b_d    = 8'd0;
assign pr_i[1].b_we   = 1'b0;
assign xy_raw         = pr_o[1].b_q;

wire       xadj = ~(ab[1] & ab[2]) ^ ab[3];
wire [7:0] xy   = ~crt_flip ? ~xy_raw :
                  ab[0]     ? xy_raw - 8'd19 :
                              xy_raw - 8'd15 + {6'd0, xadj, 1'b0};
wire [7:0] dr   = hblank ? xy : 8'hFF;

reg  [7:0] db_reg;
reg  [1:0] s26_bank_reg;
reg  [3:0] char_sum_reg;
reg        char_match_reg;
reg        char_hblank_reg;

always @(posedge clk) begin
    if (ce6 && hcnt[2:0] == 3'd3) begin
        reg [8:0] sum;
        sum = {vcnt[7:0], 1'b1} + {dr, ~hblank};
        char_sum_reg    <= (jr & ~hblank) ? {sum[4], jr_line ^ {3{flip}}} : sum[4:1];
        char_match_reg  <= (sum[8:5] == 4'hF);
        char_hblank_reg <= hblank;
        db_reg          <= db;
        s26_bank_reg    <= s26_bank;
    end
end

wire xflip = char_hblank_reg ? db_reg[1] ^ crt_flip : flip;
wire yflip = char_hblank_reg ? db_reg[0] ^ crt_flip : flip;
wire obj_on = char_match_reg | hcnt[8];

wire [12:0] ca;
assign ca[12]   = char_hblank_reg;
assign ca[11:6] = db_reg[7:2];
assign ca[5]    = char_hblank_reg ? char_sum_reg[3] ^ xflip : db_reg[1];
assign ca[4]    = char_hblank_reg ? hcnt[3] : db_reg[0];
assign ca[3]    = hcnt[2] ^ yflip;
assign ca[2]    = char_sum_reg[2] ^ xflip;
assign ca[1]    = char_sum_reg[1] ^ xflip;
assign ca[0]    = char_sum_reg[0] ^ xflip;

wire [13:0] ca_jr = {ca[12], ca[12] ? jr_spritebank : jr_charbank, ca[11:0]};

wire [7:0] gfx_q;
wire       gfx_eyes = gfx_dec[0];
wire [12:0] ca_pp = ca[12] ? {ca[12:5], ca[4:3] - 2'd1, ca[2:0]} : ca ^ 13'h0008;
wire [12:0] ca_rom = gfx_dec[1] ? ca_pp : gfx_eyes ? {ca[12:3], ca[0], ca[1], ca[2]} : ca;
wire [7:0] gfx_q2;
wire [7:0] gfx_dout = gfx_eyes   ? {gfx_q[7], gfx_q[4], gfx_q[5], gfx_q[6], gfx_q[3:0]} :
                      gfx_dec[2] ? {gfx_q2[7:4], gfx_q[3:0]} : gfx_q;
// Super ABC: gfx[i] = user1[{i12,i13,i14,0,i15,i[11:0]}], i = {region, bank, ca[11:0]}.
// Only user1 addresses with A13 clear are ever read, so they are stored at {A16:A14, A12:A0}.
wire [15:0] sabc_rd = {sabc_bank[0], sabc_bank[1], sabc_bank[2], ca[12], ca[11:0]};
wire [15:0] sabc_wr = {ioctl_addr[16:14], ioctl_addr[12:0]};
wire [15:0] sch_a = {1'b0, sch_xbank, ca[12] ? jr_spritebank : jr_charbank, ca[12], ca[11:0]};

assign gfx_a_a = dl_active ? (dl_sabc ? sabc_wr : dl_s26 ? {1'b0, ioctl_addr[14:0]} : dl_sch ? ioctl_addr[15:0] :
                              {2'b00, ioctl_addr[13:0]}) : sch ? {1'b1, sch_a[14:0]} : {3'b001, ca_rom};
assign gfx_q2  = gfx_a_q;
assign gfx_b_a = sch ? sch_a : s26 ? {1'b0, ca[12], s26_bank_reg, ca[11:0]} : sabc ? sabc_rd : bankgfx ? {2'b00, ca_jr} : {3'b000, ca_rom};
assign gfx_q   = gfx_b_q;

reg  [3:0] shift_regl, shift_regu;
reg  [3:0] shift_regl2, shift_regu2;
reg        vout_obj_on, vout_yflip, vout_hblank;
reg  [4:0] vout_db;

wire       ip        = hcnt[0] & hcnt[1];
wire [1:0] shift_sel = vout_yflip ? {ip, 1'b1} : {1'b1, ip};
wire [1:0] shift_op  = vout_yflip ? {shift_regu[0], shift_regl[0]} : {shift_regu[3], shift_regl[3]};
wire [1:0] shift_op2 = vout_yflip ? {shift_regu2[0], shift_regl2[0]} : {shift_regu2[3], shift_regl2[3]};
wire [3:0] sch_pen   = {shift_op, shift_op2};

always @(posedge clk) begin
    if (ce6) begin
        case (shift_sel)
            2'b01: begin shift_regu <= {1'b0, shift_regu[3:1]}; shift_regl <= {1'b0, shift_regl[3:1]};
                         shift_regu2 <= {1'b0, shift_regu2[3:1]}; shift_regl2 <= {1'b0, shift_regl2[3:1]}; end
            2'b10: begin shift_regu <= {shift_regu[2:0], 1'b0}; shift_regl <= {shift_regl[2:0], 1'b0};
                         shift_regu2 <= {shift_regu2[2:0], 1'b0}; shift_regl2 <= {shift_regl2[2:0], 1'b0}; end
            2'b11: begin shift_regu <= gfx_dout[7:4];            shift_regl <= gfx_dout[3:0];
                         shift_regu2 <= gfx_q2[7:4];             shift_regl2 <= gfx_q2[3:0];             end
            default: ;
        endcase

        if (hcnt[2:0] == 3'd7) begin
            vout_obj_on <= obj_on;
            vout_yflip  <= yflip;
            vout_hblank <= hblank;
            vout_db     <= db[4:0];
        end
    end
end

wire [7:0] lut_4a, lut_clock;
assign lut_a_a   = dl_active ? ioctl_addr[7:0] - 8'h20 : 8'h07;
assign lut_clock = lut_a_q;
assign lut_b_a   = {bankgfx & jr_colbank, vout_db, shift_op};
assign lut_4a    = lut_b_q;

reg  [7:0] ra, ra_t1;
reg        vout_obj_on_t1, vout_hblank_t1;
reg  [7:0] lut_4a_t1;
reg  [3:0] sch_pen_t1;
reg  [1:0] shift_op_t1;

wire cntr_ld = (hcnt[3:0] == 4'd7) & (vout_hblank | hblank | ~vout_obj_on);

always @(posedge clk) begin
    if (ce6) begin
        ra             <= cntr_ld ? dr : ra + 8'd1;
        ra_t1          <= ra;
        vout_obj_on_t1 <= vout_obj_on;
        vout_hblank_t1 <= vout_hblank;
        lut_4a_t1      <= lut_4a;
        sch_pen_t1     <= sch_pen;
        shift_op_t1    <= shift_op;
    end
end

wire [7:0] sprite_ram_q;
wire [5:0] sprite_ram_op = sprite_ram_q[5:0];
wire [5:0] sprite_ram_reg = vout_obj_on_t1 ? sprite_ram_op : 6'd0;
wire       video_op_sel   = |sprite_ram_reg[5:2];
wire [5:0] sprite_ram_ip  = ~vout_hblank_t1 ? 6'd0 :
                            video_op_sel    ? sprite_ram_reg :
                            sch             ? {sch_pen_t1, 2'b00} : {lut_4a_t1[3:0], shift_op_t1};

assign pr_i[0].a_addr = {8'd0, ra_t1};
assign pr_i[0].a_d    = {2'b00, sprite_ram_ip};
assign pr_i[0].a_we   = ce6 & vout_obj_on_t1;
assign pr_i[0].b_addr = {8'd0, ra_t1};
assign pr_i[0].b_d    = 8'd0;
assign pr_i[0].b_we   = 1'b0;
assign sprite_ram_q   = pr_o[0].b_q;

reg  [8:0] ovl_x = 9'd0;
reg  [7:0] ovl_y = 8'd0;
reg        ovl_hb = 1'b1;
always @(posedge clk) begin
    if (ce6) begin
        ovl_hb <= out_hblank;
        ovl_x  <= out_hblank ? 9'd0 : ovl_x + 9'd1;
        if (vblank)                  ovl_y <= 8'd0;
        else if (out_hblank & ~ovl_hb) ovl_y <= ovl_y + 8'd1;
    end
end

wire [8:0] ina_x0 = flip ? 9'd144 : 9'd120;
wire [7:0] ina_y0 = flip ? 8'd96  : 8'd112;
wire [8:0] act_x0 = flip ? 9'd144 : 9'd120;
wire [7:0] act_y0 = flip ? 8'd112 - {3'd0, ovl_clock[4], 4'd0} : 8'd96 + {3'd0, ovl_clock[4], 4'd0};
wire [8:0] ina_dx = ovl_x - ina_x0, act_dx0 = ovl_x - act_x0;
wire [7:0] ina_dy = ovl_y - ina_y0, act_dy0 = ovl_y - act_y0;
wire       ina_in = ovl_en && ovl_clock <= 5'd16 && ina_dx < 9'd24 && ina_dy < 8'd16;
wire       act_in = ovl_en && act_dx0 < 9'd24 && act_dy0 < 8'd16;
wire [4:0] act_dx = flip ? 5'd23 - act_dx0[4:0] : act_dx0[4:0];
wire [3:0] act_dy = flip ? 4'd15 - act_dy0[3:0] : act_dy0[3:0];

function [10:0] clk_byte(input [4:0] code, input [4:0] x, input [3:0] y);
    clk_byte = {code, (y < 4'd8 ? 6'd32 + {3'd0, y[2:0]} : {3'd0, y[2:0]} + 6'd8) +
                      (x < 5'd8 ? 6'd16 : x < 5'd16 ? 6'd8 : 6'd0)};
endfunction

wire [7:0] clk_q_a, clk_q_b;
reg  [2:0] ina_bit, act_bit;
reg        ina_on, act_on;
always @(posedge clk) begin
    ina_bit <= ina_dx[2:0];
    act_bit <= act_dx[2:0];
    ina_on  <= ina_in;
    act_on  <= act_in;
end

assign clk_a_a = dl_active ? ioctl_addr[10:0] : clk_byte(5'h1F, ina_dx[4:0], ina_dy[3:0]);
assign clk_q_a = clk_a_q;
assign clk_b_a = clk_byte(ovl_clock ^ 5'h1F, act_dx, act_dy);
assign clk_q_b = clk_b_q;

wire ovl_pix = (act_on & clk_q_b[act_bit]) | (ina_on & clk_q_a[ina_bit]);

wire [3:0] final_col = ovl_pix                            ? lut_clock[3:0] :
                       (vout_hblank | vblank)             ? 4'd0 :
                       (jr & jr_bgpri & |shift_op)        ? lut_4a[3:0] :
                       video_op_sel                       ? sprite_ram_reg[5:2] :
                       sch                                ? sch_pen : lut_4a[3:0];

wire [7:0] pm_rgb, jr_lo, jr_hi;
assign pal_a   = {bankgfx & jr_palbank, final_col};
assign pm_rgb  = pal_q;
assign jrpal_a = {jr_palbank, final_col};
assign jr_lo   = jrlo_q;
assign jr_hi   = jrhi_q;

assign rgb = pal_nib ? {jr_hi[3:0], jr_lo[3:0]} : pm_rgb;
assign pen = final_col;

endmodule
