module shift_reg
#(
    parameter WIDTH = 1, //bits per pxl
    parameter DEPTH = 1  //number of stages
}
(
    input clk,
    input rst_n,

    input  [WIDTH-1:0] pxl_in,
    output [WIDTH*DEPTH-1:0] pxl_flat_out,
    output [WIDTH-1:0] pxl_out
    
);

reg [WIDTH-1:0] shift_r[DEPTH];

assign pxl_out = shift_r[DEPTH-1]; //output 1 register at the end at a time

assign pxl_flat_out[(WIDTH*DEPTH-1) : (WIDTH*(DEPTH-1))] = shift_r[0]; //index 0 is the most sig "stage"

genvar i;
generate 

    for (i = 0; i < DEPTH-1; i++) begin: shift 

        assign 

    end

endgenerate

    always @(posedge clk or negedge rst_n) begin

        //shift 

    end


endmodule 