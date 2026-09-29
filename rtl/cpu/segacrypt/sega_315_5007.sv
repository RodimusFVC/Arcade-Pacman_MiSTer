//============================================================================
//
//  Sega 315-5007 encrypted Z80 (Pengo 315-5007 sets) - opcode/data decryption
//
//  Port of MAME pengo.cpp decode_pengo6 (BSD-3-Clause; Nicola Salmoria).
//
//    j    = {D5,D3,D1}, mirrored when D7 set
//    data = src ^ data_xor[A0][j]
//    op   = src ^ opcode_xor[{A12,A8,A4}][j]
//
//============================================================================

module sega_315_5007 (
    input       [7:0] src,       // raw ROM byte
    input      [15:0] addr,      // CPU address
    input             m1,        // 1 = opcode fetch, 0 = data read
    output      [7:0] dout
);

    wire [2:0] j = {src[5], src[3], src[1]} ^ {3{src[7]}};

    reg [7:0] dx, ox;
    always @(*) begin
        case ({addr[0], j})
            4'd0  : dx = 8'hA0;
            4'd1  : dx = 8'h82;
            4'd2  : dx = 8'h28;
            4'd3  : dx = 8'h0A;
            4'd4  : dx = 8'h82;
            4'd5  : dx = 8'hA0;
            4'd6  : dx = 8'h0A;
            4'd7  : dx = 8'h28;
            4'd8  : dx = 8'h88;
            4'd9  : dx = 8'h0A;
            4'd10 : dx = 8'h82;
            4'd11 : dx = 8'h00;
            4'd12 : dx = 8'h88;
            4'd13 : dx = 8'h0A;
            4'd14 : dx = 8'h82;
            4'd15 : dx = 8'h00;
            default: dx = 8'h00;
        endcase
        case ({addr[12], addr[8], addr[4], j})
            6'd0  : ox = 8'h02;
            6'd1  : ox = 8'h08;
            6'd2  : ox = 8'h2A;
            6'd3  : ox = 8'h20;
            6'd4  : ox = 8'h20;
            6'd5  : ox = 8'h2A;
            6'd6  : ox = 8'h08;
            6'd7  : ox = 8'h02;
            6'd8  : ox = 8'h88;
            6'd9  : ox = 8'h88;
            6'd10 : ox = 8'h00;
            6'd11 : ox = 8'h00;
            6'd12 : ox = 8'h88;
            6'd13 : ox = 8'h88;
            6'd14 : ox = 8'h00;
            6'd15 : ox = 8'h00;
            6'd16 : ox = 8'h88;
            6'd17 : ox = 8'h0A;
            6'd18 : ox = 8'h82;
            6'd19 : ox = 8'h00;
            6'd20 : ox = 8'hA0;
            6'd21 : ox = 8'h22;
            6'd22 : ox = 8'hAA;
            6'd23 : ox = 8'h28;
            6'd24 : ox = 8'h88;
            6'd25 : ox = 8'h0A;
            6'd26 : ox = 8'h82;
            6'd27 : ox = 8'h00;
            6'd28 : ox = 8'hA0;
            6'd29 : ox = 8'h22;
            6'd30 : ox = 8'hAA;
            6'd31 : ox = 8'h28;
            6'd32 : ox = 8'h2A;
            6'd33 : ox = 8'h08;
            6'd34 : ox = 8'h2A;
            6'd35 : ox = 8'h08;
            6'd36 : ox = 8'h8A;
            6'd37 : ox = 8'hA8;
            6'd38 : ox = 8'h8A;
            6'd39 : ox = 8'hA8;
            6'd40 : ox = 8'h2A;
            6'd41 : ox = 8'h08;
            6'd42 : ox = 8'h2A;
            6'd43 : ox = 8'h08;
            6'd44 : ox = 8'h8A;
            6'd45 : ox = 8'hA8;
            6'd46 : ox = 8'h8A;
            6'd47 : ox = 8'hA8;
            6'd48 : ox = 8'h88;
            6'd49 : ox = 8'h0A;
            6'd50 : ox = 8'h82;
            6'd51 : ox = 8'h00;
            6'd52 : ox = 8'hA0;
            6'd53 : ox = 8'h22;
            6'd54 : ox = 8'hAA;
            6'd55 : ox = 8'h28;
            6'd56 : ox = 8'h88;
            6'd57 : ox = 8'h0A;
            6'd58 : ox = 8'h82;
            6'd59 : ox = 8'h00;
            6'd60 : ox = 8'hA0;
            6'd61 : ox = 8'h22;
            6'd62 : ox = 8'hAA;
            6'd63 : ox = 8'h28;
            default: ox = 8'h00;
        endcase
    end

    assign dout = src ^ (m1 ? ox : dx);

endmodule
