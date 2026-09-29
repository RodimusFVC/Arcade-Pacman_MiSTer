//============================================================================
//
//  Super Chick sound board (MAME schick.cpp: Bomb Jack sound system)
//  Z80 at 3.072 MHz, 8K ROM 0000, 1K RAM 4000, sound latch 6000 (read clears),
//  NMI on vblank, three AY-3-8910 at 1.536 MHz: address on the even port, data on the odd one (00, 10, 80)
//
//============================================================================

module schick_sound
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               pause,
    input               vblank,

    input               latch_wr,       // main CPU OUT (00)
    input         [7:0] latch_din,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               dl_rom,         // "audiocpu" region write (first 8K kept)

    output signed [15:0] audio
);

// 3.072 MHz CPU, 1.536 MHz AY
reg [4:0] div = 5'd0;
always @(posedge clk) div <= div + 5'd1;
wire ce_cpu = div[3:0] == 4'd0;
wire ce_ay  = div == 5'd0;

wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire [15:0] a;
wire  [7:0] dout;
reg   [7:0] din;
reg         nmi_n = 1'b1;

T80sed cpu
(
    .RESET_n(~reset),
    .CLK_n(clk),
    .CLKEN(ce_cpu & ~pause),
    .WAIT_n(1'b1),
    .INT_n(1'b1),
    .NMI_n(nmi_n),
    .BUSRQ_n(1'b1),
    .M1_n(m1_n),
    .MREQ_n(mreq_n),
    .IORQ_n(iorq_n),
    .RD_n(rd_n),
    .WR_n(wr_n),
    .RFSH_n(rfsh_n),
    .HALT_n(),
    .BUSAK_n(),
    .A(a),
    .DI(din),
    .DO(dout)
);

// NMI follows vblank (MAME append_inputline(INPUT_LINE_NMI)); the Z80 takes it on the falling edge of NMI_n
always @(posedge clk) nmi_n <= ~vblank;

wire mem_rd = ~mreq_n & rfsh_n & ~rd_n;
wire mem_wr = ~mreq_n & rfsh_n & ~wr_n;

wire [7:0] rom_q;
dpram_dc #(.widthad_a(13)) rom
(
    .clock_a(clk),
    .address_a(ioctl_addr[12:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_rom & ioctl_addr[14:13] == 2'd0),

    .clock_b(clk),
    .address_b(a[12:0]),
    .q_b(rom_q)
);

wire [7:0] ram_q;
dpram_dc #(.widthad_a(10)) ram
(
    .clock_a(clk),
    .address_a(a[9:0]),
    .data_a(dout),
    .wren_a(mem_wr & a[15:13] == 3'b010),
    .q_a(ram_q),

    .clock_b(clk)
);

// sound latch: the main CPU writes, the sound CPU's read of 6000 clears it
reg  [7:0] latch = 8'd0;
reg        latch_rd = 1'b0;
wire       latch_cs = mem_rd & a[15:13] == 3'b011;
always @(posedge clk) begin
    latch_rd <= latch_cs;
    if (reset)                    latch <= 8'd0;
    else if (latch_wr)            latch <= latch_din;
    else if (latch_rd & ~latch_cs) latch <= 8'd0;          // clear once the read cycle ends
end

always @(*) begin
    case (a[15:13])
        3'b000:  din = rom_q;
        3'b010:  din = ram_q;
        3'b011:  din = latch;
        default: din = 8'hFF;
    endcase
end

// AY writes: one strobe per OUT cycle
reg  io_armed = 1'b1;
wire io_wr    = ~iorq_n & m1_n & ~wr_n & io_armed;
always @(posedge clk) begin
    if (iorq_n)     io_armed <= 1'b1;
    else if (io_wr) io_armed <= 1'b0;
end

wire [9:0] snd1, snd2, snd3;
jt49_bus #(.COMP(3'b010)) ay1
(
    .rst_n(~reset), .clk(clk), .clk_en(ce_ay),
    .bdir(io_wr & a[7:1] == 7'h00), .bc1(~a[0]), .din(dout), .sel(1'b1), .dout(),
    .sound(snd1), .A(), .B(), .C(), .sample(), .IOA_in(8'hFF), .IOA_out(), .IOB_in(8'hFF), .IOB_out()
);
jt49_bus #(.COMP(3'b010)) ay2
(
    .rst_n(~reset), .clk(clk), .clk_en(ce_ay),
    .bdir(io_wr & a[7:1] == 7'h08), .bc1(~a[0]), .din(dout), .sel(1'b1), .dout(),
    .sound(snd2), .A(), .B(), .C(), .sample(), .IOA_in(8'hFF), .IOA_out(), .IOB_in(8'hFF), .IOB_out()
);
jt49_bus #(.COMP(3'b010)) ay3
(
    .rst_n(~reset), .clk(clk), .clk_en(ce_ay),
    .bdir(io_wr & a[7:1] == 7'h40), .bc1(~a[0]), .din(dout), .sel(1'b1), .dout(),
    .sound(snd3), .A(), .B(), .C(), .sample(), .IOA_in(8'hFF), .IOA_out(), .IOB_in(8'hFF), .IOB_out()
);

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
