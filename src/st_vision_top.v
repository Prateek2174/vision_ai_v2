module st_vision_top
(
    input clk,
    input rst_n,

    input [7:0] left_pxl_in,
    input [7:0] right_pxl_in,

    output [] pxl_out
);

    wire [:0] left_window;
    wire [:0] right_window;

    //========================================================
    // 
    //========================================================

    st_vision_window_gen
    #(
        .WIDTH       (),        //bits per pxl
        .WINDOW_WIDTH(), //num of pixels in each row of the window
        .NUM_ROWS    (),     //num of rows in the window
        .ROW_LENGTH  ()    //num of pxls in a row/line
    )
    left_window_gen(

        //IN
        .clk   (clk),
        .rst_n (rst_n),

        .pxl_in(left_pxl_in),

        //OUT
        .pxl_out(left_window)
       
    );

    st_vision_window_gen
    #(
        .WIDTH        (),       
        .WINDOW_WIDTH (), 
        .NUM_ROWS     (),     
        .ROW_LENGTH   ()    
    )
    right_window_gen(
        //IN
        .clk   (clk),
        .rst_n (rst_n),

        .pxl_in(right_pxl_in),

        //OUT
        .pxl_out(right_window)
       
    );

    //========================================================
    // 
    //========================================================

    wire [:0] left_census;
    wire [:0] right_census;

    st_vision_census
    #(
        .WIDTH         (), //bits per pxl
        .WINDOW_WIDTH  (), //number of columns in census window / num pixels in a row
        .WINDOW_HEIGHT ()
    )
    left_cam_census(
        .clk  (clk),
        .rst_n(rst_n),

        .pxl_in  (),
        .pxl_out (left_census) //because the output is binary
    );

    st_vision_census
    #(
        .WIDTH         (), //bits per pxl
        .WINDOW_WIDTH  (), //number of columns in census window / num pixels in a row
        .WINDOW_HEIGHT ()
    )
    right_cam_census(
        .clk  (clk),
        .rst_n(rst_n),

        .pxl_in(),
        .pxl_out(right_census) //because the output is binary
    );

