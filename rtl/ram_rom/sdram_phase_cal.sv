//  Copyright (C) 2026 Rodimus

module sdram_phase_cal #(
    parameter [6:0] POS        = 7'd80,
    parameter [3:0] LATCH_MASK = 4'hF,
    parameter       QUIET_BITS = 21
)(
    input             clk,
    input             por_reset,

    input             ref_clr,
    input             ref_wd,
    input      [15:0] ref_w,              // {odd byte, even byte}

    input             ph_auto,
    input             ld_busy,            // ioctl_download | status[0] (Main holds it across the MRA)
    input             dl_active,
    input             blocked,

    output reg  [6:0] ph_req_val,
    output reg        ph_req_tgl,
    input             ph_ack,

    output            rd_go,
    output     [14:0] rd_word,
    input             rd_take,
    input             rd_cpl,
    input      [15:0] sd_dout,
    input      [15:0] sd_dout_d1,

    output reg        busy,
    output            hold
);

    function automatic [31:0] crc_step(input [31:0] c, input [15:0] d);
        integer i;
        reg [31:0] r;
        begin
            r = c;
            for (i = 15; i >= 0; i = i - 1)
                r = {r[30:0], 1'b0} ^ ((r[31] ^ d[i]) ? 32'h04C11DB7 : 32'd0);
            crc_step = r;
        end
    endfunction

    reg  [31:0] ref_crc;
    reg  [14:0] ref_cnt;
    wire        ref_take = ref_wd && !ref_cnt[14];
    wire        ref_ok   = (ref_cnt[14:4] != 11'd0);
    always_ff @(posedge clk) begin
        if (ref_clr) begin
            ref_crc <= 32'hFFFFFFFF; ref_cnt <= 15'd0;
        end else if (ref_take) begin
            ref_crc <= crc_step(ref_crc, ref_w); ref_cnt <= ref_cnt + 15'd1;
        end
    end

    localparam [2:0] CS_IDLE = 3'd0, CS_REQ = 3'd1, CS_TGL = 3'd2, CS_WACK = 3'd3,
                     CS_SETTLE = 3'd4, CS_READ = 3'd5, CS_EVAL = 3'd6, CS_PICK = 3'd7;
    reg   [2:0] st;
    reg         pend, fin, abrt, inflight, auto_d;
    reg   [6:0] p, home, tgt;
    reg  [14:0] w;
    reg  [14:0] reads;
    reg   [7:0] settle;
    reg  [21:0] wdog;
    reg  [QUIET_BITS-1:0] quiet;
    reg   [1:0] dly;
    reg  [15:0] s_e, s_n, s_l;
    reg  [31:0] crc [0:3];
    reg   [3:0] okacc;
    reg   [6:0] t_cur [0:3], t_curs [0:3], t_first [0:3], t_best [0:3], t_bests [0:3];
    reg   [3:0] t_open;
    integer     li;

    assign hold    = busy || (pend && ph_auto && ref_ok);
    assign rd_go   = busy && (st == CS_READ) && !inflight && (w != ref_cnt) && (dly == 2'd0);
    assign rd_word = w;

    wire [15:0] cw [0:3];
    assign cw[0] = s_e;
    assign cw[1] = s_n;
    assign cw[2] = s_l;
    assign cw[3] = sd_dout;

    wire [3:0] pass_now = {crc[3] == ref_crc, crc[2] == ref_crc,
                           crc[1] == ref_crc, crc[0] == ref_crc};
    wire [3:0] pass_pos = okacc & pass_now & LATCH_MASK;

    reg  [6:0] pk_len [0:3];
    reg  [6:0] pk_st  [0:3];
    reg  [6:0] pk_blen, pk_bst;
    reg  [7:0] pk_mid;
    always_comb begin
        for (li = 0; li < 4; li = li + 1) begin
            if ((t_cur[li] != 7'd0) && (t_first[li] != 7'd0) && (t_first[li] != POS) &&
                ((t_cur[li] + t_first[li]) > t_best[li])) begin
                pk_len[li] = t_cur[li] + t_first[li];
                pk_st[li]  = t_curs[li];
            end else begin
                pk_len[li] = t_best[li];
                pk_st[li]  = t_bests[li];
            end
        end
        pk_blen = pk_len[1]; pk_bst = pk_st[1];
        if (pk_len[0] > pk_blen) begin pk_blen = pk_len[0]; pk_bst = pk_st[0]; end
        if (pk_len[2] > pk_blen) begin pk_blen = pk_len[2]; pk_bst = pk_st[2]; end
        if (pk_len[3] > pk_blen) begin pk_blen = pk_len[3]; pk_bst = pk_st[3]; end
        pk_mid = {1'b0, pk_bst} + {2'b00, pk_blen[6:1]};
        if (pk_mid >= {1'b0, POS}) pk_mid = pk_mid - {1'b0, POS};
    end

    always_ff @(posedge clk) begin
        if (por_reset) begin
            st <= CS_IDLE; busy <= 1'b0; pend <= 1'b0; fin <= 1'b0; abrt <= 1'b0;
            inflight <= 1'b0; dly <= 2'd0; home <= 7'd0; quiet <= '0; auto_d <= 1'b0;
            wdog <= 22'd0; ph_req_val <= 7'd0; ph_req_tgl <= 1'b0;
        end else begin
            auto_d <= ph_auto;
            quiet  <= ld_busy ? '0 : (quiet + {{(QUIET_BITS-1){1'b0}}, ~&quiet});
            if (ref_take || (ph_auto && !auto_d)) pend <= 1'b1;
            if (busy) wdog <= wdog + 22'd1;

            if (rd_take) inflight <= 1'b1;
            if (rd_cpl) begin
                s_e <= sd_dout_d1; s_n <= sd_dout; dly <= 2'd2;
            end else if (dly == 2'd2) begin
                s_l <= sd_dout; dly <= 2'd1;
            end else if (dly == 2'd1) begin
                for (li = 0; li < 4; li = li + 1) crc[li] <= crc_step(crc[li], cw[li]);
                dly <= 2'd0; inflight <= 1'b0; w <= w + 15'd1;
                if (!reads[14]) reads <= reads + 15'd1;
            end

            if (busy && (!ph_auto || &wdog)) begin
                busy <= 1'b0; st <= CS_IDLE;
            end else if (busy && dl_active && !abrt) begin
                abrt <= 1'b1; fin <= 1'b1; tgt <= home; st <= CS_REQ;
            end else begin
                case (st)
                    CS_IDLE:
                        if (pend && ph_auto && ref_ok && (&quiet) && !blocked && !dl_active && !ld_busy) begin
                            pend <= 1'b0; busy <= 1'b1; fin <= 1'b0; abrt <= 1'b0; wdog <= 22'd0;
                            p <= 7'd0; tgt <= 7'd0; t_open <= 4'hF;
                            for (li = 0; li < 4; li = li + 1) begin
                                t_cur[li] <= 7'd0; t_curs[li] <= 7'd0; t_first[li] <= 7'd0;
                                t_best[li] <= 7'd0; t_bests[li] <= 7'd0;
                            end
                            st <= CS_REQ;
                        end
                    CS_REQ: begin
                        ph_req_val <= tgt; wdog <= 22'd0;
                        st <= CS_TGL;
                    end
                    CS_TGL: begin
                        ph_req_tgl <= ~ph_req_tgl;
                        st <= CS_WACK;
                    end
                    CS_WACK:
                        if (ph_ack) begin
                            if (fin) begin
                                busy <= 1'b0; st <= CS_IDLE;
                                if (abrt) pend <= 1'b1;
                                else      home <= tgt;
                            end else begin
                                settle <= 8'd0; st <= CS_SETTLE;
                            end
                        end
                    CS_SETTLE: begin
                        settle <= settle + 8'd1;
                        if (&settle) begin
                            w <= 15'd0; reads <= 15'd0; okacc <= 4'hF;
                            for (li = 0; li < 4; li = li + 1) crc[li] <= 32'hFFFFFFFF;
                            st <= CS_READ;
                        end
                    end
                    CS_READ:
                        if ((w == ref_cnt) && !inflight && (dly == 2'd0)) begin
                            if (reads[14]) st <= CS_EVAL;
                            else begin
                                okacc <= okacc & pass_now;
                                w <= 15'd0;
                                for (li = 0; li < 4; li = li + 1) crc[li] <= 32'hFFFFFFFF;
                            end
                        end
                    CS_EVAL: begin
                        for (li = 0; li < 4; li = li + 1) begin
                            if (pass_pos[li]) begin
                                t_cur[li] <= t_cur[li] + 7'd1;
                                if (t_cur[li] == 7'd0) t_curs[li] <= p;
                                if (t_open[li]) t_first[li] <= t_first[li] + 7'd1;
                                if ((t_cur[li] + 7'd1) > t_best[li]) begin
                                    t_best[li]  <= t_cur[li] + 7'd1;
                                    t_bests[li] <= (t_cur[li] == 7'd0) ? p : t_curs[li];
                                end
                            end else begin
                                t_cur[li] <= 7'd0; t_open[li] <= 1'b0;
                            end
                        end
                        if (p == POS - 7'd1) st <= CS_PICK;
                        else begin p <= p + 7'd1; tgt <= p + 7'd1; st <= CS_REQ; end
                    end
                    CS_PICK: begin
                        tgt <= ((pk_blen == 7'd0) || (pk_blen == POS)) ? 7'd0 : pk_mid[6:0];
                        fin <= 1'b1;
                        st  <= CS_REQ;
                    end
                endcase
            end
        end
    end

endmodule
