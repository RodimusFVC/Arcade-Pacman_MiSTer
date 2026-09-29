//============================================================================
//
//  Large ROM regions in SDRAM (ioctl index 2), read back a byte at a time
//  through sdram.sv (Sorgelig), with read-latch auto-detect
//
//============================================================================

module pacman_sdrom
(
    input               clk,            // 49.152 MHz
    input               por_reset,      // power-on only: a download must not idle this FSM

    input               ioctl_download,
    input               ioctl_wr2,      // ioctl index 2 byte
    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    output              ioctl_wait,

    // read latch: rd_auto measures which burst word completion holds; rd_mode overrides and is the fallback
    input               rd_auto,        // 1 = use the detected latch when detection succeeded
    input         [1:0] rd_mode,        // 0 Early, 1 Normal, 2 Late, 3 Later
    input               cpu_req,        // held while the CPU reads the SDRAM region
    input        [19:0] cpu_addr,       // byte address
    output reg    [7:0] cpu_data = 8'd0,
    output              cpu_busy,       // hold the CPU (WAIT) until the byte is back

    inout        [15:0] SDRAM_DQ,
    output       [12:0] SDRAM_A,
    output              SDRAM_DQML,
    output              SDRAM_DQMH,
    output        [1:0] SDRAM_BA,
    output              SDRAM_nCS,
    output              SDRAM_nWE,
    output              SDRAM_nRAS,
    output              SDRAM_nCAS,
    output              SDRAM_CKE,
    output              SDRAM_CLK
);

localparam [1:0] RD_EARLY = 2'd0, RD_NORMAL = 2'd1, RD_LATE = 2'd2, RD_LATER = 2'd3;

reg  [26:1] sd_addr = 26'd0;
reg  [15:0] sd_din = 16'd0;
reg   [1:0] sd_bs = 2'b11;
reg         sd_rd = 1'b0, sd_wr = 1'b0, sd_busy = 1'b0, sd_was_rd = 1'b0, sd_lsb = 1'b0;
reg         sd_refresh = 1'b0, sd_old_ready = 1'b1;
reg   [8:0] sd_refresh_cnt = 9'd0;
wire [15:0] sd_dout;
wire        sd_ready;

// sd_dout is a register of SDRAM_DQ, so a one-deep delay gives burst word 0
reg  [15:0] sd_dout_d1 = 16'd0;
always @(posedge clk) sd_dout_d1 <= sd_dout;

reg         wr_pend = 1'b0;
reg  [19:0] wr_addr = 20'd0;
reg   [7:0] wr_data = 8'd0;

reg  [19:0] have_addr = 20'hFFFFF;      // byte currently held in cpu_data
reg         have_ok = 1'b0;
reg         rd_pend = 1'b0;             // Late / Later capture after completion
reg   [1:0] rd_cnt = 2'd0;

// ---- read-latch auto-detect ------------------------------------------------
// Reads wrap inside the aligned 4-word block, so one block of four distinct words tells the sample points apart;
// falls back to rd_mode if no such block is seen or a read hangs
reg  [63:0] dl_blk = 64'd0;
reg  [18:0] blk_wa = 19'd0;
reg         blk_rdy = 1'b0;
always @(posedge clk) begin
    if (ioctl_wr2) dl_blk <= {dl_blk[55:0], ioctl_dout};
    if (ioctl_wr2 && ioctl_addr[2:0] == 3'd7) blk_wa <= {ioctl_addr[19:3], 2'b00};
    blk_rdy <= ioctl_wr2 && ioctl_addr[2:0] == 3'd7;
end

// dl_blk holds b0..b7 oldest-first once the 8th byte has shifted in
wire [15:0] blk_w0 = {dl_blk[55:48], dl_blk[63:56]};
wire [15:0] blk_w1 = {dl_blk[39:32], dl_blk[47:40]};
wire [15:0] blk_w2 = {dl_blk[23:16], dl_blk[31:24]};
wire [15:0] blk_w3 = {dl_blk[ 7: 0], dl_blk[15: 8]};
wire blk_distinct = (blk_w0 != blk_w1) && (blk_w0 != blk_w2) && (blk_w0 != blk_w3)
                 && (blk_w1 != blk_w2) && (blk_w1 != blk_w3) && (blk_w2 != blk_w3);

reg  [18:0] ref_wa = 19'd0;
reg  [15:0] ref_w[4];
reg         ref_vld = 1'b0;
always @(posedge clk) begin
    if (por_reset) ref_vld <= 1'b0;
    else if (blk_rdy && !ref_vld && blk_distinct) begin
        ref_wa   <= blk_wa;
        ref_w[0] <= blk_w0; ref_w[1] <= blk_w1;
        ref_w[2] <= blk_w2; ref_w[3] <= blk_w3;
        ref_vld  <= 1'b1;
    end
end

reg         probing = 1'b0, sd_probe = 1'b0, det_ok = 1'b0, dl_d = 1'b0;
reg   [1:0] prb_dly = 2'd0, prb_ph = 2'd0, rd_det = RD_NORMAL;
reg   [3:0] prb_ok = 4'hF;              // {Later, Late, Normal, Early} still matching
reg  [15:0] prb_wd, prb_e, prb_n, prb_l;
reg  [15:0] prb_to = 16'd0;

wire  [3:0] prb_ok_nxt = {prb_ok[3] && (sd_dout == prb_wd),     // completion +2
                          prb_ok[2] && (prb_l   == prb_wd),     // completion +1
                          prb_ok[1] && (prb_n   == prb_wd),     // completion
                          prb_ok[0] && (prb_e   == prb_wd)};    // completion -1

wire  [1:0] rd_sel      = (rd_auto && det_ok) ? rd_det : rd_mode;
wire [15:0] sd_dout_sel = (rd_sel == RD_EARLY) ? sd_dout_d1 : sd_dout;

assign ioctl_wait = sd_busy | wr_pend;
assign cpu_busy   = cpu_req & ~(have_ok & have_addr == cpu_addr);

always @(posedge clk) begin
    if (por_reset) begin
        sd_rd <= 1'b0; sd_wr <= 1'b0; sd_busy <= 1'b0; sd_refresh <= 1'b0; sd_refresh_cnt <= 9'd0;
        sd_old_ready <= 1'b1; wr_pend <= 1'b0; have_ok <= 1'b0; rd_pend <= 1'b0; rd_cnt <= 2'd0;
        probing <= 1'b0; sd_probe <= 1'b0; prb_dly <= 2'd0; det_ok <= 1'b0; dl_d <= 1'b0;
    end
    else begin
        // Probe once the download's last write has drained
        dl_d <= ioctl_download;
        if (dl_d && !ioctl_download && ref_vld && !wr_pend && !sd_busy) begin
            probing <= 1'b1; prb_ph <= 2'd0; prb_ok <= 4'hF; prb_to <= 16'd0;
        end
        if (probing) begin
            prb_to <= prb_to + 16'd1;
            if (&prb_to) begin              // never leave the CPU blocked
                probing <= 1'b0; sd_probe <= 1'b0; prb_dly <= 2'd0; det_ok <= 1'b0;
            end
        end

        // AUTO REFRESH: 8192 rows / 64 ms = 7.8125 us = 384 clocks at 49.152 MHz
        if (sd_refresh_cnt == 9'd383) begin
            sd_refresh_cnt <= 9'd0;
            sd_refresh     <= ~sd_refresh;
        end
        else sd_refresh_cnt <= sd_refresh_cnt + 9'd1;

        sd_old_ready <= sd_ready;
        if (ioctl_download) have_ok <= 1'b0;

        if (ioctl_wr2) begin
            wr_pend <= 1'b1;
            wr_addr <= ioctl_addr[19:0];
            wr_data <= ioctl_dout;
        end

        // accepted: ready fell, drop the strobe so the operation runs once
        if (sd_old_ready && !sd_ready) begin
            sd_rd <= 1'b0;
            sd_wr <= 1'b0;
        end

        if (sd_busy) begin
            if (sd_ready && !sd_rd && !sd_wr) begin
                if (sd_was_rd) begin
                    if (sd_probe) begin
                        prb_e <= sd_dout_d1; prb_n <= sd_dout;
                        prb_dly <= 2'd2; sd_probe <= 1'b0;
                    end
                    else if (rd_sel >= RD_LATE) begin
                        rd_pend <= 1'b1;
                        rd_cnt  <= (rd_sel == RD_LATER) ? 2'd2 : 2'd1;
                    end
                    else begin
                        cpu_data <= sd_lsb ? sd_dout_sel[15:8] : sd_dout_sel[7:0];
                        have_ok  <= 1'b1;
                    end
                end
                sd_busy <= 1'b0;
            end
        end
        else if (wr_pend) begin
            sd_addr <= {7'd0, wr_addr[19:1]};
            sd_din  <= {wr_data, wr_data};
            sd_bs   <= wr_addr[0] ? 2'b10 : 2'b01;
            sd_wr   <= 1'b1; sd_busy <= 1'b1; sd_was_rd <= 1'b0;
            wr_pend <= ioctl_wr2;                 // keep a byte arriving this cycle
        end
        else if (probing && prb_dly == 2'd0) begin
            sd_addr <= {7'd0, ref_wa + {17'd0, prb_ph}};
            prb_wd  <= ref_w[prb_ph];
            sd_rd   <= 1'b1; sd_busy <= 1'b1; sd_was_rd <= 1'b1; sd_probe <= 1'b1;
        end
        else if (cpu_busy && !ioctl_download && !probing && !rd_pend) begin
            sd_addr   <= {7'd0, cpu_addr[19:1]};
            sd_lsb    <= cpu_addr[0];
            have_addr <= cpu_addr;
            have_ok   <= 1'b0;
            sd_rd     <= 1'b1; sd_busy <= 1'b1; sd_was_rd <= 1'b1;
        end

        // Late / Later: capture one / two clocks after completion
        if (rd_pend && rd_cnt > 2'd1) rd_cnt <= rd_cnt - 2'd1;
        else if (rd_pend) begin
            cpu_data <= sd_lsb ? sd_dout[15:8] : sd_dout[7:0];
            have_ok  <= 1'b1;
            rd_pend  <= 1'b0;
        end

        // Late sample lands one clock after completion; all candidates are then in hand
        if (prb_dly == 2'd2) begin
            prb_l   <= sd_dout;                   // completion +1
            prb_dly <= 2'd1;
        end
        else if (prb_dly == 2'd1) begin
            prb_ok  <= prb_ok_nxt;                // sd_dout is now completion +2
            prb_dly <= 2'd0;
            if (prb_ph == 2'd3) begin
                probing <= 1'b0;
                if      (prb_ok_nxt[1]) begin rd_det <= RD_NORMAL; det_ok <= 1'b1; end
                else if (prb_ok_nxt[0]) begin rd_det <= RD_EARLY;  det_ok <= 1'b1; end
                else if (prb_ok_nxt[2]) begin rd_det <= RD_LATE;   det_ok <= 1'b1; end
                else if (prb_ok_nxt[3]) begin rd_det <= RD_LATER;  det_ok <= 1'b1; end
                else                          det_ok <= 1'b0;
            end
            else prb_ph <= prb_ph + 2'd1;
        end
    end
end

// 100 us startup = 4916 clocks at 49.152 MHz; refresh comes from the toggle above
sdram #(.sdram_startup_cycles(14'd4952), .cycles_per_refresh(14'd383)) sdram_i
(
    .init       (por_reset),
    .clk        (clk),
    .SDRAM_DQ   (SDRAM_DQ),   .SDRAM_A   (SDRAM_A),   .SDRAM_DQML(SDRAM_DQML),
    .SDRAM_DQMH (SDRAM_DQMH), .SDRAM_BA  (SDRAM_BA),  .SDRAM_nCS (SDRAM_nCS),
    .SDRAM_nWE  (SDRAM_nWE),  .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
    .SDRAM_CKE  (SDRAM_CKE),  .SDRAM_CLK (SDRAM_CLK), .SDRAM_EN  (1'b1),
    .sel        (1'b1),
    .addr       (sd_addr),    .dout      (sd_dout),   .din       (sd_din),
    .wr         (sd_wr),      .bs        (sd_bs),     .rd        (sd_rd),
    .ready      (sd_ready),   .refresh   (sd_refresh),
    .cpsel(1'b0), .cpaddr(26'd0), .cpdin(16'd0), .cprd(), .cpreq(1'b0), .cpbusy()
);

endmodule
