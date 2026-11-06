// Based on MAME schick.cpp (David Haywood, Nicola Salmoria, BSD-3-Clause)

module schick_sound
(
    input               clk,
    input               reset,
    input               pause,
    input               vblank,

    input               latch_wr,
    input         [7:0] latch_din,

    output       [12:0] rom_a,
    input         [7:0] rom_d,
    output ram_pool_pkg::pram_i_t pr_i,
    input  ram_pool_pkg::pram_o_t pr_o,

    output chip_pool_pkg::z80sed_i_t z80sed_1_i,
    input  chip_pool_pkg::z80sed_o_t z80sed_1_o,
    output chip_pool_pkg::ay_i_t [2:0] ay_i,
    input  chip_pool_pkg::ay_o_t [2:0] ay_o,

    output signed [15:0] audio
);

reg [4:0] div = 5'd0;
always @(posedge clk) div <= div + 5'd1;
wire ce_cpu = div[3:0] == 4'd0;
wire ce_ay  = div == 5'd0;

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire [15:0] a;
wire  [7:0] dout;
reg   [7:0] din;
reg         nmi_n = 1'b1;

assign z80sed_1_i.reset_n = ~reset;
assign z80sed_1_i.ce      = ce_cpu & ~pause;
assign z80sed_1_i.wait_n  = 1'b1;
assign z80sed_1_i.int_n   = 1'b1;
assign z80sed_1_i.nmi_n   = nmi_n;
assign z80sed_1_i.di      = din;
assign m1_n   = z80sed_1_o.m1_n;
assign mreq_n = z80sed_1_o.mreq_n;
assign iorq_n = z80sed_1_o.iorq_n;
assign rd_n   = z80sed_1_o.rd_n;
assign wr_n   = z80sed_1_o.wr_n;
assign rfsh_n = z80sed_1_o.rfsh_n;
assign a      = z80sed_1_o.a;
assign dout   = z80sed_1_o.dout;

always @(posedge clk) nmi_n <= ~vblank;

wire mem_rd = ~mreq_n & rfsh_n & ~rd_n;
wire mem_wr = ~mreq_n & rfsh_n & ~wr_n;

wire [7:0] rom_q;
assign rom_a = a[12:0];
assign rom_q = rom_d;

wire [7:0] ram_q;
assign pr_i.a_addr = {6'd0, a[9:0]};
assign pr_i.a_d    = dout;
assign pr_i.a_we   = mem_wr & a[15:13] == 3'b010;
assign pr_i.b_addr = 16'd0;
assign pr_i.b_d    = 8'd0;
assign pr_i.b_we   = 1'b0;
assign ram_q       = pr_o.a_q;

reg  [7:0] latch = 8'd0;
reg        latch_rd = 1'b0;
wire       latch_cs = mem_rd & a[15:13] == 3'b011;
always @(posedge clk) begin
    latch_rd <= latch_cs;
    if (reset)                    latch <= 8'd0;
    else if (latch_wr)            latch <= latch_din;
    else if (latch_rd & ~latch_cs) latch <= 8'd0;
end

always @(*) begin
    case (a[15:13])
        3'b000:  din = rom_q;
        3'b010:  din = ram_q;
        3'b011:  din = latch;
        default: din = 8'hFF;
    endcase
end

reg  io_armed = 1'b1;
wire io_wr    = ~iorq_n & m1_n & ~wr_n & io_armed;
always @(posedge clk) begin
    if (iorq_n)     io_armed <= 1'b1;
    else if (io_wr) io_armed <= 1'b0;
end

wire [9:0] snd1, snd2, snd3;
assign ay_i[0].bdir = io_wr & a[7:1] == 7'h00;
assign ay_i[1].bdir = io_wr & a[7:1] == 7'h08;
assign ay_i[2].bdir = io_wr & a[7:1] == 7'h40;
assign ay_i[0].ce = ce_ay;   assign ay_i[0].bc1 = ~a[0];  assign ay_i[0].din = dout;  assign ay_i[0].ioa_in = 8'hFF;  assign ay_i[0].iob_in = 8'hFF;
assign ay_i[1].ce = ce_ay;   assign ay_i[1].bc1 = ~a[0];  assign ay_i[1].din = dout;  assign ay_i[1].ioa_in = 8'hFF;  assign ay_i[1].iob_in = 8'hFF;
assign ay_i[2].ce = ce_ay;   assign ay_i[2].bc1 = ~a[0];  assign ay_i[2].din = dout;  assign ay_i[2].ioa_in = 8'hFF;  assign ay_i[2].iob_in = 8'hFF;
assign snd1 = ay_o[0].sound;
assign snd2 = ay_o[1].sound;
assign snd3 = ay_o[2].sound;

wire [11:0] mix = {2'b00, snd1} + {2'b00, snd2} + {2'b00, snd3};
jt49_dcrm2 #(.sw(16)) dcrm
(
    .clk(clk),
    .cen(ce_ay),
    .rst(reset),
    .din({mix, 4'd0}),
    .dout(audio)
);

endmodule
