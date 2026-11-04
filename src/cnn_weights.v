module cnn_weights
(
    input clk,
    input rst_n,
    input [2:0] conv_layer_sel, // WIDENED 2->3 bits: 000=CONV1, 001=CONV2,
                                 // 010=CONV3, 011=CONV4, 100=FC (was 2 bits
                                 // for 00/01/10/11 = 3 conv layers + FC,
                                 // which exactly filled 2 bits with no room
                                 // for a 4th conv layer). This same width
                                 // change is needed everywhere conv_layer_sel
                                 // is declared -- mac_array.v, cnn_top.v,
                                 // top.v -- not just here.
    input [15:0] conv_addr,     // WIDENED 13->16 bits: total conv weights
                                 // for the small arch = 108+2592+10368+20736
                                 // = 33,804, +1 padding word = 33,805 (see
                                 // mac_array.v -- the address pipeline
                                 // transiently reads one past the last
                                 // channel/filter's real taps, harmless
                                 // everywhere except the very last one,
                                 // which needs somewhere real to land).
                                 // Needs 16 bits either way (was 5,831 for
                                 // the 3-layer design)
    input [6:0] fc_addr,        // NARROWED 8->7 bits: 48 inputs * 2 outputs
                                 // = 96 (was 32*6=192, needed 8 bits; 96
                                 // fits in 7)

    input [7:0] bias_addr,      // WIDENED 6->8 bits: total biases across all
                                 // 4 layers = 12+24+48+48 = 132 (was
                                 // 8+16+32=56 for the 3-layer design, which
                                 // fit in 6 bits; 132 needs 8)

    output [7:0] data_out,
    output [7:0] bias_data_out


);

wire [7:0] conv_dout;
wire [7:0] fc_dout;
wire [7:0] bias_dout;

assign data_out = (conv_layer_sel == 3'b100) ? fc_dout : conv_dout;
assign bias_data_out = bias_dout;

    Gowin_pROM_conv conv_prom(

        .dout(conv_dout), //output [7:0] dout
        .clk(clk), //input clk
        .oce(1'b1), //input oce
        .ce(1'b1), //input ce
        .reset(~rst_n), //input reset
        .ad(conv_addr) //input [15:0] ad

    );

    Gowin_pROM_fc fc_prom(

        .dout(fc_dout), //output [7:0] dout
        .clk(clk), //input clk
        .oce(1'b1), //input oce
        .ce(1'b1), //input ce
        .reset(~rst_n), //input reset
        .ad(fc_addr) //input [6:0] ad

    );

    Gowin_pROM_bias bias_prom(
        .dout(bias_dout), //output [7:0] dout
        .clk(clk), //input clk
        .oce(1'b1), //input oce
        .ce(1'b1), //input ce
        .reset(~rst_n), //input reset
        .ad(bias_addr) //input [7:0] ad
    );

endmodule
