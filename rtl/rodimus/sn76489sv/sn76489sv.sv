//============================================================================
//  sn76489sv.sv - TI SN76489 family PSG: 3 square-wave tones + 1 noise channel, 2 dB attenuators.
//  Own work (Rodimus, 2026). Behaviour follows MAME src/devices/sound/sn76496.cpp (BSD-3-Clause, Nicola Salmoria
//  and contributors) variant by variant; see LICENSE.
//
//  VARIANT (MAME device, its constructor arguments):
//    0 SN76489           15-bit LFSR, taps 0x0001 / 0x0002, /8 input divider
//    1 SN76489A          17-bit LFSR, taps 0x0004 / 0x0008, /8
//    2 SN76496 (Y2404)   17-bit LFSR, taps 0x0004 / 0x0008, /8
//    3 SN76494           as SN76489A, no /8 divider
//    4 SN94624           as SN76489, no /8 divider
//    5 Sega VDP PSG      16-bit LFSR, taps 0x0001 / 0x0008, period 0 = 0 (TI chips: 0 = 0x400)
//    6 NCR8496           16-bit LFSR, taps 0x0002 / 0x0020, XNOR, LFSR reset only when the mode bit changes
//
//  Pins = master chip_pool_pkg sn76489_i_t / sn76489_o_t (jt89's): ce = the chip's CLOCK pin rate.
//  Timing: one update tick per 16 ce (2 ce without the /8 divider); a write is taken on the clock /CS and /WE are
//  both low after either was high; READY is low for 32 ce (4 without the divider) after it, as MAME's ready timer.
//  Output: as the real chip (and MAME), each channel v while its output bit is high, 0 while low (v = 255 x 2 dB
//  steps, 0 at attenuation 15), the four summed: 0..1020, 0 when silent. The level that follows the attenuators is
//  real (a game can play a volume-modulated ultrasonic tone); the DC goes where the board's coupling capacitor puts
//  it (MiSTer's audio_out DC blocker). Output polarity is not modelled (MAME negates the SN76489's; inaudible).
//  Reset: tones and noise silent (attenuation 15; MAME's device_start sets 0 = full volume, a power-up guess for a
//  chip with no reset pin), periods 0x400 (Sega 0), LFSR = its feedback bit, counters 0.
//============================================================================
module sn76489sv #(
    parameter int VARIANT = 0
)(
    input  logic               rst,
    input  logic               clk,
    input  logic               ce,
    input  logic               wr_n,
    input  logic               cs_n,
    input  logic         [7:0] din,
    output logic signed [10:0] sound,
    output logic               ready
);
    localparam logic [16:0] FB   = (VARIANT == 0 || VARIANT == 4) ? 17'h04000 :
                                   (VARIANT >= 1 && VARIANT <= 3) ? 17'h10000 : 17'h08000;
    localparam logic [16:0] TAP1 = (VARIANT == 0 || VARIANT == 4 || VARIANT == 5) ? 17'h00001 :
                                   (VARIANT == 6) ? 17'h00002 : 17'h00004;
    localparam logic [16:0] TAP2 = (VARIANT == 0 || VARIANT == 4) ? 17'h00002 :
                                   (VARIANT == 6) ? 17'h00020 : 17'h00008;
    localparam bit          DIV8 = !(VARIANT == 3 || VARIANT == 4);
    localparam bit          SEGA = (VARIANT == 5);
    localparam bit          NCR  = (VARIANT == 6);
    localparam logic  [3:0] TICKM = DIV8 ? 4'd15 : 4'd1;  // ce per update tick - 1 (16 / 2)
    localparam logic  [5:0] RDYN  = DIV8 ? 6'd32 : 6'd4;  // ce READY stays low after a write

    // ---- registers (MAME m_register / m_period) ----
    logic  [9:0] tone [0:2];                                // tone periods as written
    logic  [3:0] att  [0:3];                                // attenuation, 15 = off
    logic  [2:0] nctl;                                    // noise control: [2] white, [1:0] rate (bit 3 unused)
    logic  [2:0] last;                                    // latched register
    logic [10:0] per  [0:2];                                // tone period in ticks (0 -> 0x400 on TI chips)
    logic [11:0] per3;                                    // noise period in ticks
    logic [11:0] cnt  [0:3];
    logic  [3:0] out;                                     // channel output bits
    logic [16:0] rng;
    logic  [3:0] pre;                                     // ce -> tick prescaler
    logic        wr_l;
    logic  [5:0] rcnt;

    wire        wr    = ~cs_n & ~wr_n;
    wire        wr_ev = wr & ~wr_l;
    wire        tick  = ce && (pre == TICKM);
    wire  [2:0] r     = din[7] ? din[6:4] : last;         // register this write targets
    wire  [9:0] tnew  = din[7] ? {tone[r[2:1]][9:4], din[3:0]} : {din[5:0], tone[r[2:1]][3:0]};
    wire [10:0] pnew  = (tnew != 10'd0 || SEGA) ? {1'b0, tnew} : 11'h400;
    wire  [2:0] nnew  = din[2:0];                         // noise control as written (latch or data byte)
    wire [11:0] p3new = (nnew[1:0] == 2'd3) ? {per[2], 1'b0} : 12'd32 << nnew[1:0];

    // LFSR step: MAME's tap test, NCR = XNOR on the second tap
    wire        t1    = |(rng & TAP1);
    wire        t2    = NCR ? ~|(rng & TAP2) : |(rng & TAP2);
    wire [16:0] rnext = (t1 != (t2 && nctl[2])) ? ((rng >> 1) | FB) : (rng >> 1);

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 3; i++) begin tone[i] <= 10'd0; per[i] <= SEGA ? 11'd0 : 11'h400; end
            for (int i = 0; i < 4; i++) begin att[i] <= 4'hf; cnt[i] <= 12'd0; end
            nctl <= 3'd0; last <= SEGA ? 3'd3 : 3'd0; per3 <= 12'd0; out <= {3'b000, FB[0]};
            rng <= FB; pre <= 4'd0; wr_l <= 1'b0; ready <= 1'b1; rcnt <= 6'd0;
        end else begin
            wr_l <= wr;
            if (ce) pre <= (pre == TICKM) ? 4'd0 : pre + 4'd1;

            // ---- update tick (MAME sound_stream_update, one divided clock) ----
            if (tick) begin
                for (int i = 0; i < 3; i++)
                    if (cnt[i] <= 12'd1) begin out[i] <= ~out[i]; cnt[i] <= {1'b0, per[i]}; end
                    else cnt[i] <= cnt[i] - 12'd1;
                if (cnt[3] <= 12'd1) begin rng <= rnext; out[3] <= rnext[0]; cnt[3] <= per3; end
                else cnt[3] <= cnt[3] - 12'd1;
            end

            // ---- register write (MAME write()); after the tick so its LFSR reset wins on a shared clock ----
            if (wr_ev) begin
                if (din[7]) last <= din[6:4];
                case (r)
                    3'd0, 3'd2, 3'd4: begin
                        tone[r[2:1]] <= tnew;
                        per[r[2:1]]  <= pnew;
                        if (r == 3'd4 && nctl[1:0] == 2'd3) per3 <= {pnew, 1'b0};
                    end
                    3'd1, 3'd3, 3'd5, 3'd7: att[r[2:1]] <= din[3:0];
                    default: begin                         // 6: noise control
                        nctl <= nnew;
                        per3 <= p3new;
                        if (!NCR || (din[7] && din[2] != nctl[2])) rng <= FB;   // out[3] keeps its level until the next shift
                    end
                endcase
            end

            // ---- READY: low for RDY ce after a write ----
            if (wr_ev) begin ready <= 1'b0; rcnt <= RDYN; end
            else if (!ready && ce) begin
                rcnt <= rcnt - 6'd1;
                if (rcnt == 6'd1) ready <= 1'b1;
            end
        end
    end

    // ---- output: 2 dB attenuator, each channel v or 0, summed ----
    function automatic logic [7:0] vol(input logic [3:0] a);
        case (a)
            4'd0: vol = 8'd255;  4'd1: vol = 8'd203;  4'd2:  vol = 8'd161; 4'd3:  vol = 8'd128;
            4'd4: vol = 8'd102;  4'd5: vol = 8'd81;   4'd6:  vol = 8'd64;  4'd7:  vol = 8'd51;
            4'd8: vol = 8'd40;   4'd9: vol = 8'd32;   4'd10: vol = 8'd26;  4'd11: vol = 8'd20;
            4'd12: vol = 8'd16;  4'd13: vol = 8'd13;  4'd14: vol = 8'd10;  default: vol = 8'd0;
        endcase
    endfunction

    logic [9:0] ch [0:3];
    always_comb
        for (int i = 0; i < 4; i++) ch[i] = out[i] ? {2'b00, vol(att[i])} : 10'd0;

    always_ff @(posedge clk)
        if (rst) sound <= 11'sd0;
        else     sound <= $signed({1'b0, ch[0] + ch[1] + ch[2] + ch[3]});
endmodule
