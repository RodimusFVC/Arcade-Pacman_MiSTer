//============================================================================
//
//  Sega 315-5010 encrypted Z80 (Pengo) - opcode/data decryption
//
//  Port of MAME src/devices/machine/segacrpt_device.cpp (BSD-3-Clause;
//  Nicola Salmoria, David Haywood). Only D3/D5/D7 of 0000-7FFF change.
//
//    row = {A12,A8,A4,A0}                 (table pair select)
//    col = {D5,D3}, mirrored when D7 set  (entry within the pair)
//    out = (src & ~8'hA8) | (conv ^ xorval)
//
//============================================================================

module sega_315_5010 (
    input       [7:0] src,       // raw ROM byte
    input      [15:0] addr,      // CPU address
    input             m1,        // 1 = opcode fetch, 0 = data read
    output      [7:0] dout
);

    wire [3:0] row     = {addr[12], addr[8], addr[4], addr[0]};
    wire [1:0] col_raw = {src[5], src[3]};
    wire [1:0] col     = src[7] ? (2'd3 - col_raw) : col_raw;
    wire [7:0] xorval  = src[7] ? 8'hA8 : 8'h00;

    // convtable[2*row] = opcode half, convtable[2*row+1] = data half
    wire [6:0] tsel    = {row, ~m1, col};

    reg [7:0] conv;
    always @(*) begin
        case (tsel)
            7'd0  : conv = 8'hA0;
            7'd1  : conv = 8'h80;
            7'd2  : conv = 8'hA8;
            7'd3  : conv = 8'h88;
            7'd4  : conv = 8'h28;
            7'd5  : conv = 8'hA8;
            7'd6  : conv = 8'h08;
            7'd7  : conv = 8'h88;
            7'd8  : conv = 8'h28;
            7'd9  : conv = 8'hA8;
            7'd10 : conv = 8'h08;
            7'd11 : conv = 8'h88;
            7'd12 : conv = 8'hA0;
            7'd13 : conv = 8'h80;
            7'd14 : conv = 8'hA8;
            7'd15 : conv = 8'h88;
            7'd16 : conv = 8'hA0;
            7'd17 : conv = 8'h80;
            7'd18 : conv = 8'h20;
            7'd19 : conv = 8'h00;
            7'd20 : conv = 8'hA0;
            7'd21 : conv = 8'h80;
            7'd22 : conv = 8'h20;
            7'd23 : conv = 8'h00;
            7'd24 : conv = 8'h08;
            7'd25 : conv = 8'h28;
            7'd26 : conv = 8'h88;
            7'd27 : conv = 8'hA8;
            7'd28 : conv = 8'hA0;
            7'd29 : conv = 8'h80;
            7'd30 : conv = 8'hA8;
            7'd31 : conv = 8'h88;
            7'd32 : conv = 8'h08;
            7'd33 : conv = 8'h00;
            7'd34 : conv = 8'h88;
            7'd35 : conv = 8'h80;
            7'd36 : conv = 8'h28;
            7'd37 : conv = 8'hA8;
            7'd38 : conv = 8'h08;
            7'd39 : conv = 8'h88;
            7'd40 : conv = 8'hA0;
            7'd41 : conv = 8'h80;
            7'd42 : conv = 8'h20;
            7'd43 : conv = 8'h00;
            7'd44 : conv = 8'h08;
            7'd45 : conv = 8'h00;
            7'd46 : conv = 8'h88;
            7'd47 : conv = 8'h80;
            7'd48 : conv = 8'hA0;
            7'd49 : conv = 8'h80;
            7'd50 : conv = 8'h20;
            7'd51 : conv = 8'h00;
            7'd52 : conv = 8'hA0;
            7'd53 : conv = 8'h80;
            7'd54 : conv = 8'h20;
            7'd55 : conv = 8'h00;
            7'd56 : conv = 8'hA0;
            7'd57 : conv = 8'h80;
            7'd58 : conv = 8'h20;
            7'd59 : conv = 8'h00;
            7'd60 : conv = 8'h00;
            7'd61 : conv = 8'h08;
            7'd62 : conv = 8'h20;
            7'd63 : conv = 8'h28;
            7'd64 : conv = 8'h88;
            7'd65 : conv = 8'h80;
            7'd66 : conv = 8'h08;
            7'd67 : conv = 8'h00;
            7'd68 : conv = 8'hA0;
            7'd69 : conv = 8'h80;
            7'd70 : conv = 8'h20;
            7'd71 : conv = 8'h00;
            7'd72 : conv = 8'h88;
            7'd73 : conv = 8'h80;
            7'd74 : conv = 8'h08;
            7'd75 : conv = 8'h00;
            7'd76 : conv = 8'h00;
            7'd77 : conv = 8'h08;
            7'd78 : conv = 8'h20;
            7'd79 : conv = 8'h28;
            7'd80 : conv = 8'h08;
            7'd81 : conv = 8'h28;
            7'd82 : conv = 8'h88;
            7'd83 : conv = 8'hA8;
            7'd84 : conv = 8'h08;
            7'd85 : conv = 8'h28;
            7'd86 : conv = 8'h88;
            7'd87 : conv = 8'hA8;
            7'd88 : conv = 8'hA0;
            7'd89 : conv = 8'h80;
            7'd90 : conv = 8'hA8;
            7'd91 : conv = 8'h88;
            7'd92 : conv = 8'hA0;
            7'd93 : conv = 8'h80;
            7'd94 : conv = 8'h20;
            7'd95 : conv = 8'h00;
            7'd96 : conv = 8'h08;
            7'd97 : conv = 8'h00;
            7'd98 : conv = 8'h88;
            7'd99 : conv = 8'h80;
            7'd100: conv = 8'h88;
            7'd101: conv = 8'h80;
            7'd102: conv = 8'h08;
            7'd103: conv = 8'h00;
            7'd104: conv = 8'h00;
            7'd105: conv = 8'h08;
            7'd106: conv = 8'h20;
            7'd107: conv = 8'h28;
            7'd108: conv = 8'h88;
            7'd109: conv = 8'h80;
            7'd110: conv = 8'h08;
            7'd111: conv = 8'h00;
            7'd112: conv = 8'h08;
            7'd113: conv = 8'h28;
            7'd114: conv = 8'h88;
            7'd115: conv = 8'hA8;
            7'd116: conv = 8'h08;
            7'd117: conv = 8'h28;
            7'd118: conv = 8'h88;
            7'd119: conv = 8'hA8;
            7'd120: conv = 8'h08;
            7'd121: conv = 8'h00;
            7'd122: conv = 8'h88;
            7'd123: conv = 8'h80;
            7'd124: conv = 8'hA0;
            7'd125: conv = 8'h80;
            7'd126: conv = 8'h20;
            7'd127: conv = 8'h00;
            default: conv = 8'h00;
        endcase
    end

    assign dout = (src & ~8'hA8) | (conv ^ xorval);

endmodule
