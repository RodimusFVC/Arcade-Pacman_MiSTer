//  MCL86 8088 as one CPU: biu_max + mcl86_eu_core + dl2_bus (max-mode pins -> request / acknowledge bus)
//  MCL86 by Ted Fried, MicroCore Labs

module mcl86_cpu
#(
    parameter integer CYC_MUL   = 1,
    parameter integer CYC_SHIFT = 0,
    parameter integer FAST_BUS  = 0
)
(
    input  logic        clk,            // core clock
    input  logic        reset,
    input  logic        cpu_clk,        // 8088 pin clock
    input  logic        nmi,
    input  logic        intr,
    output logic        req,
    output logic  [2:0] req_type,
    output logic [19:0] req_addr,
    output logic  [7:0] req_wdata,
    input  logic  [7:0] req_rdata,
    input  logic        req_ack
);

wire [15:0] eu_biu_command, eu_biu_dataout, eu_register_r3;
wire        eu_prefix_lock, eu_flag_i;
wire        biu_done, biu_clk_counter_zero, biu_nmi_caught, biu_nmi_debounce, biu_intr;
wire  [7:0] pfq_top_byte;
wire        pfq_empty;
wire [15:0] pfq_addr_out;
wire [15:0] biu_es, biu_ss, biu_cs, biu_ds, biu_rm, biu_reg, biu_ret;
wire        ad_oe, lock_n, s6_3_mux;
wire [19:0] ad_out;
wire  [7:0] ad_in;
wire  [2:0] s2_s0;
wire        ready_in;

biu_max #(.CYC_MUL(CYC_MUL), .CYC_SHIFT(CYC_SHIFT), .FAST_BUS(FAST_BUS)) BIU
(
    .CORE_CLK_INT(clk),
    .CLK(cpu_clk), .RESET_INT(reset), .READY_IN(ready_in),
    .NMI(nmi), .INTR(intr),
    .LOCK_n(lock_n), .AD_OE(ad_oe), .AD_OUT(ad_out), .AD_IN(ad_in),
    .S6_3_MUX(s6_3_mux), .S2_S0_OUT(s2_s0),
    .EU_BIU_COMMAND(eu_biu_command), .EU_BIU_DATAOUT(eu_biu_dataout),
    .EU_REGISTER_R3(eu_register_r3), .EU_PREFIX_LOCK(eu_prefix_lock),
    .BIU_DONE(biu_done), .BIU_CLK_COUNTER_ZERO(biu_clk_counter_zero),
    .BIU_SEGMENT(), .BIU_NMI_CAUGHT(biu_nmi_caught),
    .BIU_NMI_DEBOUNCE(biu_nmi_debounce), .BIU_INTR(biu_intr),
    .PFQ_TOP_BYTE(pfq_top_byte), .PFQ_EMPTY(pfq_empty), .PFQ_ADDR_OUT(pfq_addr_out),
    .BIU_REGISTER_ES(biu_es), .BIU_REGISTER_SS(biu_ss), .BIU_REGISTER_CS(biu_cs),
    .BIU_REGISTER_DS(biu_ds), .BIU_REGISTER_RM(biu_rm), .BIU_REGISTER_REG(biu_reg),
    .BIU_RETURN_DATA(biu_ret)
);

// the EU belongs to this CPU alone (a shared EU broke DL2 and Mach 3 on hardware)
mcl86_eu_core EU
(
    .CORE_CLK_INT(clk), .RESET_INT(reset), .TEST_N_INT(1'b1),
    .EU_BIU_COMMAND(eu_biu_command), .EU_BIU_DATAOUT(eu_biu_dataout),
    .EU_REGISTER_R3(eu_register_r3), .EU_PREFIX_LOCK(eu_prefix_lock), .EU_FLAG_I(eu_flag_i),
    .BIU_DONE(biu_done), .BIU_CLK_COUNTER_ZERO(biu_clk_counter_zero),
    .BIU_NMI_CAUGHT(biu_nmi_caught), .BIU_NMI_DEBOUNCE(biu_nmi_debounce), .BIU_INTR(biu_intr),
    .PFQ_TOP_BYTE(pfq_top_byte), .PFQ_EMPTY(pfq_empty), .PFQ_ADDR_OUT(pfq_addr_out),
    .BIU_REGISTER_ES(biu_es), .BIU_REGISTER_SS(biu_ss), .BIU_REGISTER_CS(biu_cs),
    .BIU_REGISTER_DS(biu_ds), .BIU_REGISTER_RM(biu_rm), .BIU_REGISTER_REG(biu_reg),
    .BIU_RETURN_DATA(biu_ret)
);

dl2_bus busglue
(
    .clk(clk), .reset_n(~reset),
    .s2_s0(s2_s0), .s6_3_mux(s6_3_mux), .ad_out(ad_out),
    .ad_in(ad_in), .ready_in(ready_in),
    .req(req), .req_type(req_type), .req_addr(req_addr), .req_wdata(req_wdata),
    .req_rdata(req_rdata), .req_ack(req_ack)
);

endmodule
