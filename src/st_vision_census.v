//Purpose:

//Take the census transform of incoming pixel window around a center pixel produced by window_gen.v
//Census Transform:
    //for each pixel in the window:
    // if (current_pixel > center_pixel) -> 1 else 0

module st_vision_census
#(
    parameter WIDTH         = 1, //bits per pxl
    parameter WINDOW_WIDTH  = 2, //number of columns in census window / num pixels in a row
    parameter WINDOW_HEIGHT = 2
)
(
    input clk,
    input rst_n,

    input [WIDTH*WINDOW_HEIGHT*WINDOW_WIDTH-1:0] pxl_in,
    output [WINDOW_HEIGHT*WINDOW_WIDTH-1:0] pxl_out //because the output is binary
);

localparam PXL_IN_WIDTH = WIDTH*WINDOW_HEIGHT*WINDOW_WIDTH;
localparam CENTER = (WINDOW_HEIGHT*WINDOW_WIDTH - 1) / 2;

wire [WINDOW_HEIGHT*WINDOW_WIDTH-1:0] pxl_out_nxt;

wire [WIDTH-1:0] word[WINDOW_HEIGHT*WINDOW_WIDTH]; //reformat the incoming stream into an appropriate array 

//Reformat incoming steam -> array

genvar i;
generate

    for (i = 0; i < WINDOW_HEIGHT*WINDOW_WIDTH; i++) begin

        assign word[i] = pxl_in[(PXL_IN_WIDTH - WIDTH*i - 1) : (PXL_IN_WIDTH - WIDTH*(i+1))];

    end

endgenerate

//Census transform:

genvar i;
generate

    for (i = 0; i < WINDOW_HEIGHT*WINDOW_WIDTH; i++) begin

        if(i == CENTER) begin

            pxl_out_nxt[i] = 0;

        end else begin
    
            pxl_out_nxt[i] = word[i] > word[CENTER];

        end

    end

endgenerate

endmodule






