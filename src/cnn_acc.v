module cnn_acc //conv_core.v
#(
    parameter DATA_W = 8,
    parameter ACC_W = 32
)
(

    input clk,
    input rst_n,
    input acc_in_en,
    
    input signed [DATA_W*9-1:0] window_in,
    input signed [DATA_W*9-1:0] weight_in,

    output reg acc_out_en,

    output reg signed [ACC_W-1:0] acc_out

);

    integer i;
    reg signed [DATA_W-1:0] pixel [0:8];
    reg signed [DATA_W-1:0] weight  [0:8];
    reg signed [ACC_W-1:0] sum;

    always @(*) begin

        for (i=0;i<9;i=i+1) begin

            pixel[i] = window_in[(DATA_W*(9-i))-1 -: DATA_W];
            weight[i]  = weight_in[(DATA_W*(9-i))-1 -: DATA_W];

        end

    end


    always @(*) begin

        sum = 0;

        for (i = 0; i < 9; i = i + 1)
            sum = sum + pixel[i] * weight[i];

    end
    
    always @(posedge clk) begin

        if (!rst_n) begin

            acc_out   <= 0;
            acc_out_en <= 1'b0;

        end else if (acc_in_en) begin

            acc_out   <= sum;
            acc_out_en <= 1'b1;

        end else begin

            acc_out_en <= 1'b0;
        end

    end

endmodule