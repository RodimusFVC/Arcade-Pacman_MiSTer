//============================================================================
//
//  Pac-Man video: tile/sprite fetch, sprite line buffer, colour lookup
//
//  Ported from "A simulation model of Pacman hardware"
//  Copyright (c) MikeJ - January 2006 (www.fpgaarcade.com), BSD licence;
//  MiSTer merge by Alexey Melnikov (Sorgelig)
//
//============================================================================

module pacman_video
(
    input               clk,
    input               ce6,

    input         [8:0] hcnt,
    input         [8:0] vcnt,
    input        [11:0] ab,             // sync bus address
    input         [7:0] db,             // sync bus data
    input               hblank,
    input               vblank,
    input               flip,           // tile flip (game latch ^ CRT flip)
    input               crt_flip,       // mirror sprites for CRT flip
    input         [2:0] gfx_dec,        // [0] D4/D6 and A0/A2 swapped, [1] Ponpoko byte order, [2] crush4 split planes
    input               dl_active,      // ROM download in progress (port A belongs to the loader)
    input               out_hblank,     // displayed hblank (counts the overlay's pixel positions)
    input               ovl_en,         // Ali Baba: mystery clock shown
    input         [4:0] ovl_clock,      // Ali Baba: mystery clock value
    input               spr_xy_we,      // CPU write to 5060-506F (sync bus phase)

    // banked boards: Jr. Pac-Man (latch 2 at 5070, scrolling playfield) and Pengo
    input               bankgfx,        // 16K gfx, bank bit below the tile/sprite region; colour table and palette banks
    input               jr,             // Jr. Pac-Man playfield: scrolled line, background priority
    input               pal_nib,        // palette from two 4-bit PROMs (Jr. Pac-Man 9E/9F)
    input               sabc,           // Super ABC: 64K gfx, 3-bit bank for tiles and sprites
    input         [2:0] sabc_bank,
    input               jr_charbank,
    input               jr_spritebank,
    input               jr_palbank,
    input               jr_colbank,
    input               jr_bgpri,       // playfield pens over sprites
    input         [2:0] jr_line,        // playfield line within the tile, scroll and flip applied
    input               s26,            // S2650 boards: 32K gfx, 2-bit tile bank per column / sprite code bits 6-7
    input         [1:0] s26_bank,
    input               sch,            // Super Chick: 4bpp (planes 2/3 +0x8000 in a 64K gfx1), gfx bank {9050/9060, Q7}
    input               sch_xbank,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               dl_gfx,         // gfx1 region write
    input               dl_pal,         // palette PROM write (proms 0x00-0x1F)
    input               dl_lut,         // colour lookup PROM write (proms 0x20-0x11F)
    input               dl_jr_lo,       // Jr palette PROM 9E (low nibble)
    input               dl_jr_hi,       // Jr palette PROM 9F (high nibble)
    input               dl_clock,       // Ali Baba clock graphics (gfx2)
    input               dl_sabc,        // Super ABC gfx (user1, 128K)
    input               dl_s26,         // S2650 boards gfx1 (32K)
    input               dl_sch,         // Super Chick gfx1 (64K)

    output        [7:0] rgb,            // palette PROM byte: B[7:6] G[5:3] R[2:0]
    output        [3:0] pen             // Super Chick: 4bpp pen (palette PROMs undumped)
);

// sprite X/Y registers (5060-506F)
wire [7:0] xy_raw;
dpram_dc #(.widthad_a(4)) sprite_xy_ram
(
    .clock_a(clk),
    .address_a(ab[3:0]),
    .data_a(db),
    .wren_a(ce6 & spr_xy_we),

    .clock_b(clk),
    .address_b(ab[3:0]),
    .q_b(xy_raw)
);

wire       xadj = ~(ab[1] & ab[2]) ^ ab[3];
wire [7:0] xy   = ~crt_flip ? ~xy_raw :
                  ab[0]     ? xy_raw - 8'd19 :
                              xy_raw - 8'd15 + {6'd0, xadj, 1'b0};
wire [7:0] dr   = hblank ? xy : 8'hFF;

// character / sprite address generation
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

wire [13:0] ca_jr = {ca[12], ca[12] ? jr_spritebank : jr_charbank, ca[11:0]};   // Jr: 16K, bank bit below the region

wire [7:0] gfx_q;
wire       gfx_eyes = gfx_dec[0];
// Ponpoko: character halves swapped, sprite 8-byte blocks rotated by one
wire [12:0] ca_pp = ca[12] ? {ca[12:5], ca[4:3] - 2'd1, ca[2:0]} : ca ^ 13'h0008;
wire [12:0] ca_rom = gfx_dec[1] ? ca_pp : gfx_eyes ? {ca[12:3], ca[0], ca[1], ca[2]} : ca;
wire [7:0] gfx_q2;
wire [7:0] gfx_dout = gfx_eyes   ? {gfx_q[7], gfx_q[4], gfx_q[5], gfx_q[6], gfx_q[3:0]} :
                      gfx_dec[2] ? {gfx_q2[7:4], gfx_q[3:0]} : gfx_q;   // crush4: plane 0 sits in the ROM's upper half
// Super ABC (MAME init_superabc): gfx[i] = user1[{i12,i13,i14,0,i15,i[11:0]}], i = {region, bank, ca[11:0]}.
// Only user1 addresses with A13 clear are ever read, so they are stored at {A16:A14, A12:A0}.
wire [15:0] sabc_rd = {sabc_bank[0], sabc_bank[1], sabc_bank[2], ca[12], ca[11:0]};
wire [15:0] sabc_wr = {ioctl_addr[16:14], ioctl_addr[12:0]};
// Super Chick: gfx bank n = {9050/9060, Q7} at n * 0x2000, sprites +0x1000; planes 2/3 in the upper 32K
wire [15:0] sch_a = {1'b0, sch_xbank, ca[12] ? jr_spritebank : jr_charbank, ca[12], ca[11:0]};

dpram_dc #(.widthad_a(16)) gfx_rom
(
    .clock_a(clk),
    .address_a(dl_active ? (dl_sabc ? sabc_wr : dl_s26 ? {1'b0, ioctl_addr[14:0]} : dl_sch ? ioctl_addr[15:0] :
                            {2'b00, ioctl_addr[13:0]}) : sch ? {1'b1, sch_a[14:0]} : {3'b001, ca_rom}),
    .data_a(ioctl_dout),
    .wren_a(dl_gfx | (dl_sabc & ~ioctl_addr[13]) | dl_s26 | dl_sch),
    .q_a(gfx_q2),

    .clock_b(clk),
    .address_b(sch ? sch_a : s26 ? {1'b0, ca[12], s26_bank_reg, ca[11:0]} : sabc ? sabc_rd : bankgfx ? {2'b00, ca_jr} : {3'b000, ca_rom}),
    .q_b(gfx_q)
);

// 2bpp shift registers (planes packed four pixels per nibble)
reg  [3:0] shift_regl, shift_regu;
reg  [3:0] shift_regl2, shift_regu2;                    // Super Chick planes 2/3
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

// colour lookup PROM (4A)
wire [7:0] lut_4a, lut_clock;
dpram_dc #(.widthad_a(8)) col_rom_4a
(
    .clock_a(clk),
    .address_a(dl_active ? ioctl_addr[7:0] - 8'h20 : 8'h07),   // idle: colour 1 pen 3 for the Ali Baba clock
    .data_a(ioctl_dout),
    .wren_a(dl_lut),
    .q_a(lut_clock),

    .clock_b(clk),
    .address_b({bankgfx & jr_colbank, vout_db, shift_op}),
    .q_b(lut_4a)
);

// sprite line buffer: read-modify-write at ra_t1, cleared as it is displayed
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
                            sch             ? {sch_pen_t1, 2'b00} : {lut_4a_t1[3:0], shift_op_t1};   // Super Chick: pen 0 transparent

dpram_dc #(.widthad_a(8)) sprite_ram
(
    .clock_a(clk),
    .address_a(ra_t1),
    .data_a({2'b00, sprite_ram_ip}),
    .wren_a(ce6 & vout_obj_on_t1),

    .clock_b(clk),
    .address_b(ra_t1),
    .q_b(sprite_ram_q)
);

// Ali Baba mystery clock (MAME alibaba_state::draw_clock): two 24x16 gfx2 cells over everything, pen 3 only
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

wire [8:0] ina_x0 = flip ? 9'd144 : 9'd120;                                    // inactive half, code 1F
wire [7:0] ina_y0 = flip ? 8'd96  : 8'd112;
wire [8:0] act_x0 = flip ? 9'd144 : 9'd120;                                    // active half, code clock ^ 1F
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

dpram_dc #(.widthad_a(11)) clock_rom
(
    .clock_a(clk),
    .address_a(dl_active ? ioctl_addr[10:0] : clk_byte(5'h1F, ina_dx[4:0], ina_dy[3:0])),
    .data_a(ioctl_dout),
    .wren_a(dl_clock),
    .q_a(clk_q_a),

    .clock_b(clk),
    .address_b(clk_byte(ovl_clock ^ 5'h1F, act_dx, act_dy)),
    .q_b(clk_q_b)
);

wire ovl_pix = (act_on & clk_q_b[act_bit]) | (ina_on & clk_q_a[ina_bit]);

wire [3:0] final_col = ovl_pix                            ? lut_clock[3:0] :
                       (vout_hblank | vblank)             ? 4'd0 :
                       (jr & jr_bgpri & |shift_op)        ? lut_4a[3:0] :           // Jr: opaque playfield pens on top
                       video_op_sel                       ? sprite_ram_reg[5:2] :
                       sch                                ? sch_pen : lut_4a[3:0];

// palette PROM (7F); Jr. Pac-Man: two 4-bit PROMs (9E low, 9F high), 32 colours, bank on latch 2 Q0
wire [7:0] pm_rgb, jr_lo, jr_hi;
dpram_dc #(.widthad_a(5)) col_rom_7f
(
    .clock_a(clk),
    .address_a(ioctl_addr[4:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_pal),

    .clock_b(clk),
    .address_b({bankgfx & jr_palbank, final_col}),
    .q_b(pm_rgb)
);

dpram_dc #(.widthad_a(5)) jr_pal_lo
(
    .clock_a(clk),
    .address_a(ioctl_addr[4:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_jr_lo),

    .clock_b(clk),
    .address_b({jr_palbank, final_col}),
    .q_b(jr_lo)
);

dpram_dc #(.widthad_a(5)) jr_pal_hi
(
    .clock_a(clk),
    .address_a(ioctl_addr[4:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_jr_hi),

    .clock_b(clk),
    .address_b({jr_palbank, final_col}),
    .q_b(jr_hi)
);

assign rgb = pal_nib ? {jr_hi[3:0], jr_lo[3:0]} : pm_rgb;
assign pen = final_col;

endmodule
