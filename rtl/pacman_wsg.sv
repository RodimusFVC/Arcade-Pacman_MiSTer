//============================================================================
//
//  Namco WSG (Pac-Man 3-voice waveform sound generator)
//
//  Ported from "A simulation model of Pacman hardware"
//  Copyright (c) MikeJ - January 2006 (www.fpgaarcade.com), BSD licence
//
//============================================================================

module pacman_wsg
(
    input               clk,
    input               ce6,            // 6.144 MHz, gated by pause
    input         [8:0] hcnt,

    input         [3:0] ab,             // sync bus address
    input         [3:0] db,             // sync bus data
    input               wr0,            // 5040-504F: accumulators / frequencies / waveforms
    input               wr1,            // 5050-505F: frequencies / volumes
    input               sound_on,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               dl_wave,        // waveform PROM (1M) write

    output reg signed [15:0] audio = 16'sd0
);

reg  [5:0] accum_reg;

wire [3:0] addr = hcnt[1] ? hcnt[5:2]      : ab;
wire [3:0] data = hcnt[1] ? accum_reg[4:1] : db;

// sequencer PROM (3M): one nibble per hcnt[5:4] slot
reg  [15:0] rom3m_n;
reg   [3:0] rom3m_w;
always @(*) begin
    rom3m_w = 4'h0;
    case (hcnt[3:0])
        4'h0: rom3m_n = 16'h0008;
        4'h1: begin rom3m_n = 16'h0000; rom3m_w = 4'h2; end
        4'h2: rom3m_n = 16'h1111;
        4'h3: rom3m_n = 16'h2222;
        4'h4: rom3m_n = 16'h0000;
        4'h5: begin rom3m_n = 16'h0000; rom3m_w = 4'h2; end
        4'h6: rom3m_n = 16'h1101;
        4'h7: rom3m_n = 16'h2242;
        4'h8: rom3m_n = 16'h0080;
        4'h9: begin rom3m_n = 16'h0000; rom3m_w = 4'h2; end
        4'hA: rom3m_n = 16'h1011;
        4'hB: rom3m_n = 16'h2422;
        4'hC: rom3m_n = 16'h0800;
        4'hD: begin rom3m_n = 16'h0000; rom3m_w = 4'h2; end
        4'hE: rom3m_n = 16'h0111;
        4'hF: rom3m_n = 16'h4222;
    endcase
end

wire [3:0] rom3m = wr0 ? rom3m_w : rom3m_n[hcnt[5:4]*4 +: 4];

wire [7:0] vol_ram_q, frq_ram_q;
wire [3:0] vol_ram_dout = vol_ram_q[3:0];
wire [3:0] frq_ram_dout = frq_ram_q[3:0];

dpram_dc #(.widthad_a(4)) vol_ram
(
    .clock_a(clk),
    .address_a(addr),
    .data_a({4'd0, data}),
    .wren_a(ce6 & wr1),

    .clock_b(clk),
    .address_b(addr),
    .q_b(vol_ram_q)
);

dpram_dc #(.widthad_a(4)) frq_ram
(
    .clock_a(clk),
    .address_a(addr),
    .data_a({4'd0, data}),
    .wren_a(ce6 & rom3m[1]),

    .clock_b(clk),
    .address_b(addr),
    .q_b(frq_ram_q)
);

wire [5:0] sum = {1'b0, vol_ram_dout, 1'b1} + {1'b0, frq_ram_dout, accum_reg[5]};

always @(posedge clk) begin
    if (ce6) begin
        if (rom3m[3])      accum_reg <= 6'd0;
        else if (rom3m[0]) accum_reg <= {sum[5:1], accum_reg[4]};
    end
end

wire [7:0] wave;
dpram_dc #(.widthad_a(8)) wave_rom
(
    .clock_a(clk),
    .address_a(ioctl_addr[7:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_wave),

    .clock_b(clk),
    .address_b({frq_ram_dout[2:0], accum_reg[4:0]}),
    .q_b(wave)
);

// the three voices are output in hcnt[5:4] slots 1..3; mix them as signed samples
reg signed [8:0] voice [3];
wire signed [8:0] sample = ($signed({5'd0, wave[3:0]}) - 9'sd8) * $signed({5'd0, vol_ram_dout});

always @(posedge clk) begin
    if (ce6) begin
        if (!sound_on) begin
            voice[0] <= 9'sd0;
            voice[1] <= 9'sd0;
            voice[2] <= 9'sd0;
        end
        else if (rom3m[2] && hcnt[5:4] != 2'd0) begin
            voice[hcnt[5:4] - 2'd1] <= sample;
        end
        audio <= (voice[0] + voice[1] + voice[2]) * 16'sd80;
    end
end

endmodule
