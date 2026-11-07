//Produces a window of pixels from the input stream

module st_vision_window_gen
#(
    parameter WIDTH        = 1, //bits per pxl
    parameter WINDOW_WIDTH = 1, //num of pixels in each row of the window
    parameter NUM_ROWS     = 1, //num of rows in the window
    parameter ROW_LENGTH   = 1  //num of pxls in a row/line
)
(
    input clk,
    input rst_n,

    input  [WIDTH-1:0] pxl_in,
    output [WIDTH*NUM_ROWS*WINDOW_WIDTH - 1:0] pxl_out
   
);

    localparam OUT_WIDTH = WIDTH*NUM_ROWS*WINDOW_WIDTH;
    localparam TAP_WIDTH = WIDTH*WINDOW_WIDTH;

    wire [WIDTH*WINDOW_WIDTH-1:0] window_row [NUM_ROWS];

    genvar i;

    generate

        for(i = 1; i < NUM_ROWS; i++) begin



        end
    endgenerate

endmodule