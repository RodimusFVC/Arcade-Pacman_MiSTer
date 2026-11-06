// s2650sv_all.sv - generated from s2650sv.sv and s2650sv_s2650_cpu.sv by verify/make_all.sh

//------------------------------------------------------------------------------
// s2650sv : Signetics 2650A / 2650B CPU, SystemVerilog
//
// Cycle-for-cycle re-implementation of "sgs2650" (Signetics 2650A CPU, "DO 4/2018",
// TEMlib, dev@temlib.org; the core in MiSTer-devel Arcadia), as used by the MiSTer
// fleet through its s2650_cpu wrapper, including the fleet's two fixes (fetch after
// an I/O access from IAR as a read; ZBRR / ZBSR indirect). Every pin, every clock
// matches that core, including where it differs from silicon or MAME (see REPORT.md).
//
// Bus: one clock per access. req/ad/wr/dw/mio/ene/dc are combinational: between
// acks they hold the pending access, during an ack they already show the next one.
// Read data is taken from dr in the cycle of the next ack.
//
// VER_B=0: 2650A (fleet default, PSU bits 4:3 read 0). VER_B=1: 2650B (PSU bits 4:3
// are user flags; sgs2650 implements nothing else of the -B, LDPL / STPL included).
//------------------------------------------------------------------------------

module s2650sv #(
    parameter bit VER_B    = 1'b0,
    parameter bit RAS_MLAB = 1'b1   // return stack in one MLAB (1) or in registers (0)
) (
    input  logic        clk,
    input  logic        reset,
    output logic        req,
    input  logic        ack,
    output logic [14:0] ad,
    output logic        wr,
    output logic  [7:0] dw,
    input  logic  [7:0] dr,
    output logic        mio,     // 1 memory, 0 I/O
    output logic        ene,     // 1 extended I/O
    output logic        dc,      // 1 data, 0 control I/O
    output logic  [1:0] ph,      // 00 code, 01 data, 10 indirect, 11 I/O (registered)
    input  logic        irq,
    output logic        intack,
    input  logic  [7:0] ivec,
    input  logic        sense,
    output logic        flag
);

    localparam logic [1:0] PH_CODE = 2'b00;
    localparam logic [1:0] PH_DATA = 2'b01;
    localparam logic [1:0] PH_IND  = 2'b10;
    localparam logic [1:0] PH_IO   = 2'b11;

    // One-hot state; the sOPCODE bit is stored inverted so that power-up (all 0) is sOPCODE
    localparam int S_OPC  = 0;
    localparam int S_IMM  = 1;
    localparam int S_IMM2 = 2;
    localparam int S_IND  = 3;
    localparam int S_IND2 = 4;
    localparam int S_WAIT = 5;
    localparam int S_DATA = 6;
    localparam int S_IO   = 7;
    localparam int S_EXE  = 8;
    localparam int S_INT  = 9;
    localparam int S_HALT = 10;
    localparam logic [10:0] ST_INV = 11'b00000000001;

    // Decoded instruction (sgs2650_pack opcode table: format, instruction, length), one bit each
    localparam int D_LEN2  =  0;  // 2-byte
    localparam int D_LEN3  =  1;  // 3-byte
    localparam int D_FMT_I =  2;  // 2-byte immediate (I / EI), else relative (R / ER)
    localparam int D_ALU   =  3;  // LOD EOR AND IOR ADD SUB COM
    localparam int D_STR   =  4;  // STR, NOP, C4-C7
    localparam int D_ROT   =  5;
    localparam int D_DAR   =  6;
    localparam int D_TMI   =  7;
    localparam int D_IO    =  8;
    localparam int D_CPPS  =  9;  // CPSU CPSL PPSU PPSL
    localparam int D_TPS   = 10;
    localparam int D_SPS   = 11;
    localparam int D_LPS   = 12;  // also 90, 91
    localparam int D_RET   = 13;
    localparam int D_HALT  = 14;
    localparam int D_BCTF  = 15;  // BCTx, BCFx
    localparam int D_BRN   = 16;
    localparam int D_BIDR  = 17;  // BIRx, BDRx
    localparam int D_BSTF  = 18;  // BSTx, BSFx
    localparam int D_BSN   = 19;
    localparam int D_ZBRR  = 20;
    localparam int D_ZBSR  = 21;
    localparam int D_BXA   = 22;
    localparam int D_BSXA  = 23;
    localparam int D_W     = 24;

    function automatic logic [D_W-1:0] decode(input logic [7:0] op);
        logic [D_W-1:0] d;
        d = '0;
        if (!op[4]) begin
            // even rows: LOD EOR AND IOR ADD SUB (STR) COM in Z / I / R / A, 40 = HALT
            d[D_STR]  = op[7:5] == 3'b110;
            d[D_HALT] = op == 8'h40;
            d[D_ALU]  = op[7:5] != 3'b110 && op != 8'h40;
            d[D_LEN2] = op[3] ^ op[2];
            d[D_LEN3] = op[3] & op[2];
            d[D_FMT_I] = ~op[3] & op[2];
        end else if (op[3]) begin
            // odd rows, columns 8-F: conditional branches, R (len 2) or B (len 3); 9B BB 9F BF
            d[D_LEN2] = ~op[2];
            d[D_LEN3] = op[2];
            case (op)
                8'h9B:   d[D_ZBRR] = 1'b1;
                8'hBB:   d[D_ZBSR] = 1'b1;
                8'h9F:   d[D_BXA]  = 1'b1;
                8'hBF:   d[D_BSXA] = 1'b1;
                default:
                    case (op[7:5])
                        3'b000, 3'b100: d[D_BCTF] = 1'b1;
                        3'b001, 3'b101: d[D_BSTF] = 1'b1;
                        3'b010:         d[D_BRN]  = 1'b1;
                        3'b011:         d[D_BSN]  = 1'b1;
                        default:        d[D_BIDR] = 1'b1;
                    endcase
            endcase
        end else begin
            // odd rows, columns 0-7
            case ({op[7:5], op[2]})
                4'b000_0: begin d[D_SPS] = op[1]; d[D_LEN3] = ~op[1]; end   // 10 11 LDPL STPL: never executed
                4'b000_1,
                4'b001_1: d[D_RET]  = 1'b1;
                4'b100_0: d[D_LPS]  = 1'b1;                                   // also 90, 91
                4'b100_1: d[D_DAR]  = 1'b1;
                4'b011_1: begin d[D_CPPS] = 1'b1; d[D_LEN2] = 1'b1; d[D_FMT_I] = 1'b1; end
                4'b101_1: begin d[D_TPS]  = 1'b1; d[D_LEN2] = 1'b1; d[D_FMT_I] = 1'b1; end
                4'b111_1: begin d[D_TMI]  = 1'b1; d[D_LEN2] = 1'b1; d[D_FMT_I] = 1'b1; end
                4'b010_0,
                4'b110_0: d[D_ROT]  = 1'b1;
                4'b010_1,
                4'b110_1: begin d[D_IO] = 1'b1; d[D_LEN2] = 1'b1; d[D_FMT_I] = 1'b1; end   // REDE WRTE
                default:  d[D_IO]   = 1'b1;                                   // REDC REDD WRTC WRTD
            endcase
        end
        decode = d;
    endfunction

    // CC from a value: 00 zero, 01 positive, 10 negative
    function automatic logic [1:0] sign8(input logic [7:0] v);
        sign8 = (v == 8'h00) ? 2'b00 : (v[7] ? 2'b10 : 2'b01);
    endfunction

    //--------------------------------------------------------------------------
    // Registers
    logic [10:0] stq;                  // state, ST_INV-encoded
    logic  [7:0] ri, rh;
    logic [D_W-1:0] dec;               // decode(ri), registered with ri
    logic        taken;                // branch condition, registered with ri
    logic  [1:0] ru;                   // index mode (2nd byte bits 6:5)
    logic [14:0] iar, ad_i;
    logic  [7:0] dw_i;
    logic        wr_i, req_i, indexed, intp;
    logic  [1:0] ph_i;
    logic  [7:0] r0, r1, r2, r3, r1b, r2b, r3b;
    logic  [7:0] psl;
    logic        psu_s, psu_f, psu_ii;
    logic  [1:0] psu_uf;
    logic  [2:0] psu_sp;
    logic [14:0] rras;

    logic  [7:0] psu;
    assign psu = {psu_s, psu_f, psu_ii, psu_uf, psu_sp};

    //--------------------------------------------------------------------------
    // Combinational
    logic [10:0] st, st_c;
    logic [D_W-1:0] dec_dr;
    logic        go, cond_v, taken_dr;
    logic  [1:0] nrd_sel, nrd_c;
    logic  [7:0] rs_v, rs_dr, rd_c, idx_v, inc_v, alu_a, alu_b, alu_r, alu_p, ps_v;
    logic  [1:0] alu_n;
    // rd_c / psl_c sources, one-hot as for ad_c; P_CC = PSL with a new CC, picked by ccs
    localparam int R_ALU = 0, R_INC = 1, R_DR = 2, R_R0 = 3, R_ROT = 4, R_DAR = 5, R_PS = 6;
    localparam int P_HOLD = 0, P_ALU = 1, P_ROT = 2, P_CLR = 3, P_SET = 4, P_R0 = 5, P_CC = 6;
    localparam int C_TMI = 0, C_TPS = 1, C_DR = 2, C_R0 = 3, C_DAR = 4, C_PS = 5;
    logic  [6:0] rds, pss;
    logic  [5:0] ccs;
    logic  [1:0] cc_x;
    function automatic logic [6:0] sel7(input int k); sel7 = 7'd1 << k; endfunction
    function automatic logic [5:0] sel6(input int k); sel6 = 6'd1 << k; endfunction
    logic  [7:0] rot_r, rot_p, dar_r, psl_c, psu_c;
    logic        rd_maj_c, pushsub_c, popsub_c, req_c, wr_c, mio_c, indexed_c, intp_c;
    logic  [7:0] dw_c, rh_c;
    logic  [1:0] ru_c, ph_c;
    // ad_c / iar_c sources, selected one-hot (flat AND-OR mux instead of a priority chain)
    localparam int A_HOLD = 0, A_INC = 1, A_IAR = 2, A_IARP1 = 3, A_IVEC = 4, A_DR = 5, A_REL = 6, A_ZREL = 7,
                   A_ABS = 8, A_PTR = 9, A_IDX = 10, A_RRAS = 11;
    localparam int I_HOLD = 0, I_P1 = 1, I_M1 = 2, I_REL = 3, I_ZREL = 4, I_PTR = 5, I_IDX = 6, I_RRAS = 7, I_IVEC = 8;
    logic [11:0] ads;
    logic  [8:0] ias;
    function automatic logic [11:0] sel12(input int k); sel12 = 12'd1 << k; endfunction
    function automatic logic  [8:0] sel9(input int k);  sel9  = 9'd1 << k;  endfunction
    logic [14:0] iar_c, ad_c, iar_p1, rel_v, zrel_v, ivec_v, abs_v, ptr_v, idx_ad;

    assign st     = stq ^ ST_INV;
    assign dec_dr = decode(dr);
    assign go     = ack | ~req_i;

    // Source register (field ri[1:0]); while fetching, only WRTC / WRTD use one, selected by dr[1:0]
    function automatic logic [7:0] regsel(input logic [1:0] n, input logic rs, input logic [7:0] q0, q1, q2, q3,
                                         q1b, q2b, q3b);
        case (n)
            2'b01:   regsel = rs ? q1b : q1;
            2'b10:   regsel = rs ? q2b : q2;
            2'b11:   regsel = rs ? q3b : q3;
            default: regsel = q0;
        endcase
    endfunction
    assign rs_v    = regsel(ri[1:0], psl[4], r0, r1, r2, r3, r1b, r2b, r3b);
    assign rs_dr   = regsel(dr[1:0], psl[4], r0, r1, r2, r3, r1b, r2b, r3b);
    assign nrd_sel = ri[1:0];   // sgs2650 uses dr[1:0] while fetching, where no register is written

    assign cond_v = (ri[1:0] == psl[7:6]) | (ri[1:0] == 2'b11);
    // Branch condition, evaluated on the opcode while fetching and registered with ri (registers and PSL
    // cannot change between the fetch and sIMM / sIMM2, where it is used)
    function automatic logic branch_taken(input logic [2:0] f, input logic [1:0] n, input logic [7:0] r,
                                          input logic [1:0] cc);
        logic c;
        c = (n == cc) | (n == 2'b11);
        case (f[2:1])
            2'b00:   branch_taken = c;
            2'b10:   branch_taken = ~c;
            2'b01:   branch_taken = r != 8'h00;
            default: branch_taken = r != (f[0] ? 8'h01 : 8'hFF);    // BIRx / BDRx: rn+-1 != 0
        endcase
    endfunction
    assign taken_dr = branch_taken(dr[7:5], dr[1:0], rs_dr, psl[7:6]);

    // Shared datapath pieces
    assign iar_p1 = iar + 15'd1;
    assign rel_v  = iar_p1 + {{8{dr[6]}}, dr[6:0]};
    assign zrel_v = {2'b00, {6{dr[6]}}, dr[6:0]};
    assign ivec_v = {2'b00, {6{ivec[6]}}, ivec[6:0]};
    assign abs_v  = {iar[14:13], rh[4:0], dr};       // ALU / STR absolute: current page
    assign ptr_v  = {rh[6:0], dr};                   // branches, indirect pointers

    // +1 / -1: BIRx / BDRx (ri[5]) and auto increment / decrement index (ru)
    assign inc_v = (st[S_IMM2] | st[S_IND2]) & (dec[D_ALU] | dec[D_STR]) ?
                   (ru[1] ? rs_v - 8'd1 : rs_v + 8'd1) :
                   (ri[5] ? rs_v - 8'd1 : rs_v + 8'd1);
    assign idx_v  = (dec[D_ALU] | dec[D_STR]) ? ((ru == 2'b11) ? rs_v : inc_v) : rs_v;
    assign idx_ad = ((st[S_IMM2] & (dec[D_ALU] | dec[D_STR])) ? abs_v : ptr_v) + {7'd0, idx_v};

    // ALU (op_alu): sIMM rn<op>imm, sDATA rn|r0<op>mem, sEXE r0<op>rn
    assign alu_n = (st[S_EXE] | (st[S_DATA] & indexed)) ? 2'b00 : ri[1:0];
    assign alu_a = regsel(alu_n, psl[4], r0, r1, r2, r3, r1b, r2b, r3b);
    assign alu_b = st[S_EXE] ? rs_v : dr;

    logic [7:0] vt, dar_t;
    always_comb begin
        alu_p = psl;
        vt    = alu_a;
        alu_r = alu_a;
        case (ri[7:5])
            3'b000: begin vt = alu_b;         alu_r = vt; end
            3'b001: begin vt = alu_a ^ alu_b; alu_r = vt; end
            3'b010: begin vt = alu_a & alu_b; alu_r = vt; end
            3'b011: begin vt = alu_a | alu_b; alu_r = vt; end
            3'b100: begin
                vt       = alu_a + alu_b + {7'd0, psl[0] & psl[3]};
                alu_r    = vt;
                alu_p[0] = (alu_a[7] & alu_b[7]) | (~vt[7] & (alu_a[7] | alu_b[7]));
                alu_p[2] = (alu_a[7] & alu_b[7] & ~vt[7]) | (~alu_a[7] & ~alu_b[7] & vt[7]);
                alu_p[5] = vt[3:0] < alu_a[3:0];
            end
            3'b101: begin
                vt       = alu_a - alu_b - {7'd0, ~psl[0] & psl[3]};
                alu_r    = vt;
                alu_p[0] = ~((~alu_a[7] & alu_b[7]) | (vt[7] & (~alu_a[7] | alu_b[7])));
                alu_p[2] = (alu_a[7] & ~alu_b[7] & ~vt[7]) | (~alu_a[7] & alu_b[7] & vt[7]);
                alu_p[5] = vt[3:0] <= alu_a[3:0];
            end
            3'b110: begin vt = alu_b; alu_r = vt; end
            default: begin // COM: 1=logical (unsigned), 0=arithmetic
                vt = alu_a - alu_b;
                if (vt == 8'h00)
                    alu_p[7:6] = 2'b00;
                else if (psl[1] ? ((~alu_a[7] & alu_b[7]) | (vt[7] & ~(alu_a[7] & ~alu_b[7]))) :
                                  ((alu_a[7] & ~alu_b[7]) | (~alu_a[7] & ~alu_b[7] & vt[7]) |
                                   (alu_a[7] & alu_b[7] & ~vt[7])))
                    alu_p[7:6] = 2'b10;
                else
                    alu_p[7:6] = 2'b01;
            end
        endcase
        if (ri[7:5] != 3'b111)
            alu_p[7:6] = sign8(vt);
    end

    // RRR (ri[7]=0) / RRL (ri[7]=1), through carry when WC
    always_comb begin
        rot_p = psl;
        if (ri[7]) begin
            if (psl[3]) begin
                rot_r    = {rs_v[6:0], psl[0]};
                rot_p[0] = rs_v[7];
                rot_p[5] = rs_v[4];
            end else
                rot_r = {rs_v[6:0], rs_v[7]};
        end else begin
            if (psl[3]) begin
                rot_r    = {psl[0], rs_v[7:1]};
                rot_p[0] = rs_v[0];
                rot_p[5] = rs_v[6];
            end else
                rot_r = {rs_v[0], rs_v[7:1]};
        end
        rot_p[7:6] = sign8(rot_r);
    end

    always_comb begin
        dar_t = psl[0] ? rs_v : rs_v + 8'hA0;
        dar_r = psl[5] ? dar_t : {dar_t[7:4], dar_t[3:0] + 4'hA};
    end

    //--------------------------------------------------------------------------
    always_comb begin
        rd_maj_c  = 1'b0;
        rds       = '0;   // rd_c is a don't care unless rd_maj_c
        pushsub_c = 1'b0;
        popsub_c  = 1'b0;
        pss       = sel7(P_HOLD);
        ccs       = '0;
        psu_c     = psu;
        ias       = sel9(I_HOLD);
        st_c      = st;
        ads       = sel12(A_HOLD);
        wr_c      = wr_i;
        dw_c      = dw_i;
        ph_c      = ph_i;
        mio_c     = 1'b1;
        rh_c      = rh;
        ru_c      = ru;
        indexed_c = indexed;
        req_c     = 1'b1;
        intp_c    = intp;
        nrd_c     = nrd_sel;

        if (go) begin
            unique case (1'b1)
                //--------------------------------------
                st[S_OPC]: begin
                    indexed_c = 1'b0;
                    ias = sel9(I_P1);
                    ads = sel12(A_IARP1);
                    wr_c      = 1'b0;
                    dw_c      = 8'h00;
                    ph_c      = PH_CODE;
                    intp_c    = 1'b0;
                    st_c      = '0;
                    if (irq & ~psu_ii) begin
                        st_c[S_INT] = 1'b1;
                        ias = sel9(I_M1);
                        ads = sel12(A_IVEC);
                    end else if (dec_dr[D_LEN2] | dec_dr[D_LEN3]) begin
                        st_c[S_IMM] = 1'b1;
                    end else if (dec_dr[D_IO]) begin  // REDC REDD WRTC WRTD
                        st_c[S_IO]  = 1'b1;
                        ads = '0;
                        dw_c        = rs_dr;
                        wr_c        = dr[7];
                        mio_c       = 1'b0;
                        ph_c        = PH_IO;
                    end else begin
                        st_c[S_EXE] = 1'b1;
                    end
                end

                //--------------------------------------
                st[S_IMM]: begin
                    ias = sel9(I_P1);
                    ads = sel12(A_IARP1);
                    wr_c  = 1'b0;
                    dw_c  = rs_v;
                    ph_c  = PH_CODE;
                    rh_c  = dr;
                    ru_c  = dr[6:5];
                    if (dec[D_LEN3]) begin
                        st_c = '0; st_c[S_IMM2] = 1'b1;
                    end else if (dec[D_FMT_I]) begin
                        // Immediate. C4-C7 (STR) match nothing: stays in sIMM, reading on
                        if (dec[D_ALU]) begin
                            st_c = '0; st_c[S_OPC] = 1'b1;
                            rd_maj_c = 1'b1;
                            rds = sel7(R_ALU);
                            pss = sel7(P_ALU);
                        end
                        if (dec[D_TMI]) begin
                            st_c = '0; st_c[S_WAIT] = 1'b1;
                            pss = sel7(P_CC); ccs = sel6(C_TMI);
                        end
                        if (dec[D_IO]) begin  // REDE WRTE
                            st_c = '0; st_c[S_IO] = 1'b1;
                            ads = sel12(A_DR);
                            wr_c  = ri[7];
                            mio_c = 1'b0;
                            ph_c  = PH_IO;
                        end
                        if (dec[D_CPPS]) begin
                            st_c = '0; st_c[S_WAIT] = 1'b1;
                            case (ri[1:0])
                                2'b00:   psu_c = psu & ~dr;
                                2'b01:   pss   = sel7(P_CLR);
                                2'b10:   psu_c = psu | dr;
                                default: pss   = sel7(P_SET);
                            endcase
                        end
                        if (dec[D_TPS]) begin
                            st_c = '0; st_c[S_WAIT] = 1'b1;
                            pss = sel7(P_CC); ccs = sel6(C_TPS);
                        end
                    end else begin
                        // Relative
                        ru_c = 2'b00;
                        if (dec[D_ALU] | dec[D_STR]) begin
                            ads = sel12(A_REL);
                            st_c = '0;
                            if (dr[7]) begin
                                st_c[S_IND] = 1'b1;
                                ph_c        = PH_IND;
                            end else begin
                                st_c[S_DATA] = 1'b1;
                                ph_c         = PH_DATA;
                                wr_c         = dec[D_STR];
                            end
                        end
                        if (dec[D_BCTF] | dec[D_BRN] | dec[D_BIDR]) begin
                            rd_maj_c = ri[7:6] == 2'b11;
                            rds      = sel7(R_INC);
                        end
                        if (dec[D_BCTF] | dec[D_BRN] | dec[D_BIDR] | dec[D_BSTF] | dec[D_BSN] |
                            dec[D_ZBRR] | dec[D_ZBSR]) begin
                            st_c = '0;
                            if (taken | dec[D_ZBRR] | dec[D_ZBSR]) begin
                                pushsub_c = dec[D_BSTF] | dec[D_BSN] | dec[D_ZBSR];
                                ads = sel12((dec[D_ZBRR] | dec[D_ZBSR]) ? A_ZREL : A_REL);
                                ias = sel9((dec[D_ZBRR] | dec[D_ZBSR]) ? I_ZREL : I_REL);
                                if (dr[7]) begin
                                    ph_c        = PH_IND;
                                    st_c[S_IND] = 1'b1;
                                end else begin
                                    ph_c         = PH_CODE;
                                    st_c[S_WAIT] = 1'b1;
                                end
                            end else
                                st_c[S_WAIT] = 1'b1;
                        end
                    end
                end

                //--------------------------------------
                st[S_IMM2]: begin
                    ias = sel9(I_P1);
                    ads = sel12(A_IARP1);
                    wr_c  = 1'b0;
                    dw_c  = rs_v;
                    if (dec[D_ALU] | dec[D_STR]) begin
                        st_c = '0;
                        if (rh[7]) begin
                            st_c[S_IND] = 1'b1;
                            ads = sel12(A_ABS);
                            ph_c        = PH_IND;
                        end else begin
                            st_c[S_DATA] = 1'b1;
                            ph_c         = PH_DATA;
                            wr_c         = dec[D_STR];
                            indexed_c    = (ru != 2'b00);
                            ads = sel12((ru == 2'b00) ? A_ABS : A_IDX);
                            if (ru == 2'b01 || ru == 2'b10) begin
                                rds      = sel7(R_INC);
                                rd_maj_c = 1'b1;
                            end
                            if (dec[D_STR] && ru != 2'b00)
                                dw_c = (ru != 2'b11 && ri[1:0] == 2'b00) ? inc_v : r0;
                        end
                    end
                    if (dec[D_BCTF] | dec[D_BRN] | dec[D_BIDR]) begin
                        rd_maj_c = ri[7:6] == 2'b11;
                        rds = sel7(R_INC);
                    end
                    if (dec[D_BCTF] | dec[D_BRN] | dec[D_BIDR] | dec[D_BSTF] | dec[D_BSN]) begin
                        st_c = '0;
                        if (taken) begin
                            pushsub_c = dec[D_BSTF] | dec[D_BSN];
                            if (rh[7]) begin
                                ads = sel12(A_PTR);
                                ph_c        = PH_IND;
                                st_c[S_IND] = 1'b1;
                                if (dec[D_BCTF] | dec[D_BRN] | dec[D_BIDR])
                                    ias = sel9(I_PTR);
                            end else begin
                                ias = sel9(I_PTR);
                                ads = sel12(A_PTR);
                                ph_c        = PH_CODE;
                                st_c[S_OPC] = 1'b1;
                            end
                        end else
                            st_c[S_OPC] = 1'b1;
                    end
                    if (dec[D_BXA] | dec[D_BSXA]) begin
                        pushsub_c = dec[D_BSXA];
                        st_c      = '0;
                        if (rh[7]) begin
                            st_c[S_IND] = 1'b1;
                            ads = sel12(A_PTR);
                            ph_c        = PH_IND;
                        end else begin
                            ias = sel9(I_IDX);
                            ads = sel12(A_IDX);
                            ph_c        = PH_CODE;
                            st_c[S_OPC] = 1'b1;
                        end
                    end
                    // LDPL / STPL match nothing: stays in sIMM2, reading on
                end

                //--------------------------------------
                st[S_DATA]: begin
                    st_c = '0; st_c[S_OPC] = 1'b1;
                    ph_c = PH_CODE;
                    ads = sel12(A_IAR);
                    wr_c = 1'b0;
                    if (dec[D_ALU]) begin
                        if (indexed)
                            nrd_c = 2'b00;
                        rd_maj_c = 1'b1;
                        rds      = sel7(R_ALU);
                        pss      = sel7(P_ALU);
                    end
                end

                //--------------------------------------
                st[S_IO]: begin
                    st_c = '0; st_c[S_OPC] = 1'b1;
                    ads = sel12(A_IAR);
                    ph_c = PH_CODE;
                    wr_c = 1'b0;
                    if (~ri[7]) begin
                        rds      = sel7(R_DR);
                        rd_maj_c = 1'b1;
                        pss      = sel7(P_CC); ccs = sel6(C_DR);
                    end
                end

                //--------------------------------------
                st[S_IND]: begin
                    st_c = '0; st_c[S_IND2] = 1'b1;
                    ads = sel12(A_INC);
                    rh_c = dr;
                end

                st[S_IND2]: begin
                    ads = sel12(A_IAR);
                    dw_c = rs_v;
                    if (intp) begin
                        st_c = '0; st_c[S_OPC] = 1'b1;
                        ias = sel9(I_PTR);
                        ads = sel12(A_PTR);
                        ph_c  = PH_CODE;
                    end else begin
                        if (dec[D_ALU] | dec[D_STR]) begin
                            st_c = '0; st_c[S_DATA] = 1'b1;
                            ph_c      = PH_DATA;
                            wr_c      = dec[D_STR] ? 1'b1 : wr_i;
                            indexed_c = (ru != 2'b00);
                            ads = sel12((ru == 2'b00) ? A_PTR : A_IDX);
                            if (ru != 2'b00)
                                dw_c = r0;
                            if (ru == 2'b01 || ru == 2'b10) begin
                                rds      = sel7(R_INC);
                                rd_maj_c = 1'b1;
                            end
                        end
                        if (dec[D_BCTF] | dec[D_BRN] | dec[D_BIDR] | dec[D_BSTF] | dec[D_BSN] |
                            dec[D_ZBRR] | dec[D_ZBSR] | dec[D_BXA] | dec[D_BSXA]) begin
                            st_c = '0; st_c[S_OPC] = 1'b1;
                            ias = sel9((dec[D_BXA] | dec[D_BSXA]) ? I_IDX : I_PTR);
                            ads = sel12((dec[D_BXA] | dec[D_BSXA]) ? A_IDX : A_PTR);
                            ph_c  = PH_CODE;
                        end
                    end
                end

                //--------------------------------------
                st[S_EXE]: begin
                    st_c = '0; st_c[S_OPC] = 1'b1;
                    if (dec[D_ALU]) begin
                        nrd_c    = 2'b00;
                        rd_maj_c = 1'b1;
                        rds      = sel7(R_ALU);
                        pss      = sel7(P_ALU);
                    end
                    if (dec[D_STR]) begin
                        rd_maj_c = 1'b1;
                        rds      = sel7(R_R0);
                        if (ri[1:0] != 2'b00) begin
                            pss = sel7(P_CC); ccs = sel6(C_R0);
                        end
                    end
                    if (dec[D_ROT]) begin
                        rd_maj_c = 1'b1;
                        rds      = sel7(R_ROT);
                        pss      = sel7(P_ROT);
                    end
                    if (dec[D_DAR]) begin
                        rd_maj_c   = 1'b1;
                        rds        = sel7(R_DAR);
                        pss        = sel7(P_CC); ccs = sel6(C_DAR);
                        st_c = '0; st_c[S_WAIT] = 1'b1;
                    end
                    if (dec[D_RET]) begin
                        if (cond_v) begin
                            ias = sel9(I_RRAS);
                            ads = sel12(A_RRAS);
                            popsub_c = 1'b1;
                            if (ri[5])
                                psu_c[5] = 1'b0;
                        end
                        st_c = '0; st_c[S_WAIT] = 1'b1;
                    end
                    if (dec[D_SPS]) begin
                        nrd_c      = 2'b00;
                        rd_maj_c   = 1'b1;
                        rds        = sel7(R_PS);
                        pss        = sel7(P_CC); ccs = sel6(C_PS);
                    end
                    if (dec[D_LPS]) begin
                        if (ri[0])
                            pss   = sel7(P_R0);
                        else
                            psu_c = r0;
                    end
                    if (dec[D_HALT]) begin
                        st_c = '0; st_c[S_HALT] = 1'b1;
                    end
                end

                st[S_WAIT]: begin
                    st_c = '0; st_c[S_OPC] = 1'b1;
                    ph_c = PH_CODE;
                end

                //--------------------------------------
                st[S_INT]: begin
                    intp_c    = 1'b1;
                    psu_c[5]  = 1'b1;
                    pushsub_c = 1'b1;
                    ru_c      = 2'b00;
                    st_c      = '0;
                    if (ivec[7]) begin  // sgs2650: pointer address taken from dr, not ivec
                        ias = sel9(I_ZREL);
                        ads = sel12(A_ZREL);
                        st_c[S_IND] = 1'b1;
                        ph_c        = PH_IND;
                    end else begin
                        ias = sel9(I_IVEC);
                        ads = sel12(A_IVEC);
                        ph_c        = PH_CODE;
                        st_c[S_OPC] = 1'b1;
                    end
                end

                //--------------------------------------
                st[S_HALT]: begin
                    if (irq & ~psu_ii) begin
                        st_c = '0; st_c[S_INT] = 1'b1;
                    end
                    req_c = 1'b0;
                end

                default: ;
            endcase
        end
    end

    always_comb begin
        ad_c = ({15{ads[A_HOLD]}}  & ad_i)            | ({15{ads[A_INC]}}  & (ad_i + 15'd1)) |
               ({15{ads[A_IAR]}}   & iar)             | ({15{ads[A_IARP1]}} & iar_p1)       |
               ({15{ads[A_IVEC]}}  & ivec_v)          | ({15{ads[A_DR]}}   & {7'd0, dr})    |
               ({15{ads[A_REL]}}   & rel_v)           | ({15{ads[A_ZREL]}} & zrel_v)        |
               ({15{ads[A_ABS]}}   & abs_v)           | ({15{ads[A_PTR]}}  & ptr_v)         |
               ({15{ads[A_IDX]}}   & idx_ad)          | ({15{ads[A_RRAS]}} & rras);
        iar_c = ({15{ias[I_HOLD]}} & iar)             | ({15{ias[I_P1]}}   & iar_p1)        |
                ({15{ias[I_M1]}}   & (iar - 15'd1))   | ({15{ias[I_REL]}}  & rel_v)         |
                ({15{ias[I_ZREL]}} & zrel_v)          | ({15{ias[I_PTR]}}  & ptr_v)         |
                ({15{ias[I_IDX]}}  & idx_ad)          | ({15{ias[I_RRAS]}} & rras)          |
                ({15{ias[I_IVEC]}} & ivec_v);
    end

    assign ps_v = ri[0] ? psl : psu;
    always_comb begin
        rd_c = ({8{rds[R_ALU]}} & alu_r) | ({8{rds[R_INC]}} & inc_v) | ({8{rds[R_DR]}}  & dr) |
               ({8{rds[R_R0]}}  & r0)    | ({8{rds[R_ROT]}} & rot_r) | ({8{rds[R_DAR]}} & dar_r) |
               ({8{rds[R_PS]}}  & ps_v);
        cc_x = ({2{ccs[C_TMI]}} & (((rs_v & dr) == dr) ? 2'b00 : 2'b10)) |
               ({2{ccs[C_TPS]}} & (((ps_v & dr) == dr) ? 2'b00 : 2'b10)) |
               ({2{ccs[C_DR]}}  & sign8(dr))    | ({2{ccs[C_R0]}} & sign8(r0)) |
               ({2{ccs[C_DAR]}} & sign8(dar_r)) | ({2{ccs[C_PS]}} & sign8(ps_v));
        psl_c = ({8{pss[P_HOLD]}} & psl)         | ({8{pss[P_ALU]}} & alu_p)        |
                ({8{pss[P_ROT]}}  & rot_p)       | ({8{pss[P_CLR]}} & (psl & ~dr))  |
                ({8{pss[P_SET]}}  & (psl | dr))  | ({8{pss[P_R0]}}  & r0)           |
                ({8{pss[P_CC]}}   & {cc_x, psl[5:0]});
    end

    //--------------------------------------------------------------------------
    // Return address stack: 8 x 15, written at SP, read (registered) at SP-1
    logic [2:0] ras_ra;
    logic [14:0] ras_q;
    assign ras_ra = psu_sp - 3'd1;

    generate
        if (RAS_MLAB) begin : g_ras_mlab
            (* ramstyle = "MLAB, no_rw_check" *) logic [14:0] ras [0:7];
            always_ff @(posedge clk)
                if (pushsub_c)
                    ras[psu_sp] <= iar_p1;
            assign ras_q = ras[ras_ra];
        end else begin : g_ras_reg
            (* ramstyle = "logic" *) logic [14:0] ras [0:7];
            always_ff @(posedge clk)
                if (pushsub_c)
                    ras[psu_sp] <= iar_p1;
            assign ras_q = ras[ras_ra];
        end
    endgenerate

    //--------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        stq <= st_c ^ ST_INV;
        if (st[S_OPC]) begin
            ri    <= dr;
            dec   <= dec_dr;     // = decode(ri) wherever it is used (outside sOPCODE)
            taken <= taken_dr;
        end
        iar     <= iar_c;
        rh      <= rh_c;
        ru      <= ru_c;
        ph_i    <= ph_c;
        indexed <= indexed_c;
        intp    <= intp_c;
        intack  <= st[S_INT];
        ad_i    <= ad_c;
        wr_i    <= wr_c;
        dw_i    <= dw_c;
        req_i   <= req_c;
        rras    <= ras_q;

        if (rd_maj_c) begin
            case (nrd_c)
                2'b01:   if (psl[4]) r1b <= rd_c; else r1 <= rd_c;
                2'b10:   if (psl[4]) r2b <= rd_c; else r2 <= rd_c;
                2'b11:   if (psl[4]) r3b <= rd_c; else r3 <= rd_c;
                default: r0 <= rd_c;
            endcase
        end

        psl    <= psl_c;
        psu_f  <= psu_c[6];
        psu_ii <= psu_c[5];
        psu_sp <= psu_c[2:0];
        if (pushsub_c)
            psu_sp <= psu_sp + 3'd1;
        if (popsub_c)
            psu_sp <= psu_sp - 3'd1;
        psu_s  <= sense;

        if (reset) begin
            ad_i   <= 15'd0;
            iar    <= 15'd0;
            psu_ii <= 1'b0;
            psu_sp <= 3'd0;
            psl[4] <= 1'b0;
            stq    <= '0;
            psu_f  <= 1'b0;
        end
    end

    // PSU bits 4:3: user flags on the -B, constant 0 on the -A
    generate
        if (VER_B) begin : g_uf
            always_ff @(posedge clk)
                psu_uf <= reset ? 2'b00 : psu_c[4:3];
        end else begin : g_nouf
            assign psu_uf = 2'b00;
        end
    endgenerate

    //--------------------------------------------------------------------------
    assign req  = req_c;
    assign ad   = ad_c;
    assign dw   = dw_c;
    assign wr   = wr_c;
    assign mio  = mio_c;
    assign dc   = ri[6];
    assign ene  = ri[2];
    assign ph   = ph_i;
    assign flag = psu_f;

endmodule

//------------------------------------------------------------------------------
// s2650sv_s2650_cpu : drop-in for the fleet's s2650_cpu wrapper (sgs2650, TEMlib "DO"),
// same ports, no parameters, 2650A
//------------------------------------------------------------------------------

module s2650sv_s2650_cpu (
    input  logic        clk,
    input  logic        reset,
    output logic        req,
    input  logic        ack,
    output logic [14:0] ad,
    output logic        wr,
    output logic  [7:0] dw,
    input  logic  [7:0] dr,
    output logic        mio,
    output logic        ene,
    output logic        dc,
    output logic  [1:0] ph,
    input  logic        irq,
    output logic        intack,
    input  logic  [7:0] ivec,
    input  logic        sense,
    output logic        flag
);

    s2650sv #(.VER_B(1'b0)) cpu (
        .clk(clk), .reset(reset), .req(req), .ack(ack), .ad(ad), .wr(wr), .dw(dw), .dr(dr),
        .mio(mio), .ene(ene), .dc(dc), .ph(ph), .irq(irq), .intack(intack), .ivec(ivec),
        .sense(sense), .flag(flag)
    );

endmodule
