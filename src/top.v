module top(
    input wire clk,
    input wire rst_n, //Active low
    output led_1,  // DONE LED
    output led_2,  // READY LED

    // =============================================================================
    // OV9
    // =============================================================================
        
    inout wire cam_scl, //I2C clock to camera this is also Display 2
    inout wire cam_sda, //I2C data to camera this is also Display 2

    input cam_vsync, //cam vsync
	input cam_href,  //cam hsync refrence, data valid
	input cam_pclk,  //cam pixel clock
    
    output cam_xclk, //clock to camera 
	
    input[7:0] cam_data, //camera data
	
    output cam_rst_n, //camera reset 
	output cam_pwdn,  //camera power down
//	output lcd_data_en //lcd data enable  

    // =============================================================================
    // FLCOS
    // =============================================================================

    input wire btn,

    output lcd_dclk,
	output lcd_hs,      //lcd horizontal synchronization
	output lcd_vs,      //lcd vertical synchronization 
	output wire [7:0] y_data,            
	output wire [7:0] cbcr_data,

    output wire VCC,    // controls display power, VCC, VIO, DAVCC, VCCX
    
    inout wire sda_0, // Display 1
    inout wire scl_0, // Display 1


);

    wire cam1_16bit_wr_en;
    wire cam2_16bit_wr_en;

    wire [7:0] y_cam1;
    wire [7:0] cbcr_cam1;
    wire [7:0] y_cam2;
    wire [7:0] cbcr_cam2;

    dvp_capture dvp_capture_left(
        
        .rst_n      (rst_n),
        .pclk       (cam_pclk),
        .input_data (cam_data),
        .de_i       (cam_href),

        .y_data     (y_cam1),
        .cbcr_data  (cbcr_cam1),

    //    .out_data   (out_data),
        .hblank     (),
        .de_o       (cam1_16bit_wr_en)
    );

    dvp_capture dvp_capture_right(
        
        .rst_n      (rst_n),
        .pclk       (),
        .input_data (),
        .de_i       (),

        .y_data     (y_cam2),
        .cbcr_data  (cbcr_cam2),

    //    .out_data   (out_data),
        .hblank     (),
        .de_o       (cam2_16bit_wr_en)
    );

    //========================================================
    // CNN COMPUTE PIPELINE
    //========================================================

    wire        conv_en;
    wire        conv_done;
    wire        gap_en;
    wire        gap_done;
    wire        fc_en;
    wire        fc_done;
    wire [2:0]  conv_layer_sel; // WIDENED 2->3 bits, see weight_rom.v/cnn_top.v
    wire        class_result;   // NARROWED 3 bits -> 1 bit (2 classes, not 6)

    cnn_top cnn_top_1 (

        .rst_n (rst_n),
        .pclk  (clk),
        .frame_ready (frame_ready),

        .conv_done (conv_done),
        .pool_done (1'b0),
        .gap_done  (gap_done),
        .fc_done   (fc_done),
        .uart_done (1'b0),

        .conv_en (conv_en),
        .pool_en (),
        .gap_en  (gap_en),
        .fc_en   (fc_en),
        .uart_en (),

        .conv_layer_sel (conv_layer_sel),

        .busy (cnn_busy)

    );

    //========================================================
    // WEIGHT ROM
    //========================================================

    wire [15:0] conv_addr;    // WIDENED 13->16 bits, see weight_rom.v
    wire [6:0]  fc_addr;      // NARROWED 8->7 bits, see weight_rom.v
    wire [7:0]  weight_data;
    wire [7:0]  bias_addr;    // WIDENED 6->8 bits, see weight_rom.v
    wire signed [7:0]  bias_data;

    cnn_weights weights (

        .clk            (clk),
        .rst_n          (rst_n),
        .conv_layer_sel (conv_layer_sel),
        .conv_addr      (conv_addr),
        .fc_addr        (fc_addr),
        .bias_addr      (bias_addr),

        .data_out       (weight_data),
        .bias_data_out  (bias_data)

    );

    //========================================================
    // FEATURE MAPS BSRAMS
    //========================================================

    wire map_a_wr_en;
    wire map_b_wr_en;
    wire map_c_wr_en;
    wire map_d_wr_en;

    wire map_a_rd_en;
    wire map_b_rd_en;
    wire map_c_rd_en;
    wire map_d_rd_en;

    wire [7:0] map_a_din;
    wire [7:0] map_b_din;
    wire [7:0] map_c_din;
    wire [7:0] map_d_din;
    
    wire [7:0] map_a_dout;
    wire [7:0] map_b_dout;
    wire [7:0] map_c_dout;
    wire [7:0] map_d_dout;

    wire [12:0] map_a_wr_addr;
    wire [11:0] map_b_wr_addr;
    wire [10:0] map_c_wr_addr;
    wire [8:0]  map_d_wr_addr;

    wire [12:0] map_a_rd_addr;
    wire [11:0] map_b_rd_addr;
    wire [10:0] map_c_rd_addr;
    wire [8:0]  map_d_rd_addr;

    cnn_mac cnn_mac_1 (

        .rst_n          (rst_n),
        .clk            (clk),
        .conv_layer_sel (conv_layer_sel),
        .conv_en        (conv_en),

        .conv_done      (conv_done),

        .resize_dout  (resize_dout),
        .resize_addr  (resize_addr),
        .resize_rd_en (resize_rd_en),

        .map_a_wr_en (map_a_wr_en),
        .map_b_wr_en (map_b_wr_en),
        .map_c_wr_en (map_c_wr_en),
        .map_d_wr_en (map_d_wr_en),   // NEW

        .map_a_rd_en (map_a_rd_en),
        .map_b_rd_en (map_b_rd_en),
        .map_c_rd_en (map_c_rd_en),   // CHANGED: now connected, mac_array
                                       // reads C as conv4's input (was left
                                       // unused in the 3-layer design)

        .map_a_din (map_a_din),
        .map_b_din (map_b_din),
        .map_c_din (map_c_din),
        .map_d_din (map_d_din),       // NEW

        .map_a_dout (map_a_dout),
        .map_b_dout (map_b_dout),
        .map_c_dout (map_c_dout),

        .map_a_wr_addr (map_a_wr_addr),
        .map_b_wr_addr (map_b_wr_addr),
        .map_c_wr_addr (map_c_wr_addr),
        .map_d_wr_addr (map_d_wr_addr), // NEW

        .map_a_rd_addr (map_a_rd_addr),
        .map_b_rd_addr (map_b_rd_addr),
        .map_c_rd_addr (map_c_rd_addr), // CHANGED: now connected

        .weight_data (weight_data),
        .conv_addr   (conv_addr),

        .bias_data   (bias_data),
        .bias_addr   (bias_addr)

    );

    //========================================================
    // GLOBAL AVERAGE POOL + CLASSIFIER
    //========================================================

    wire [5:0] gap_addr;  // WIDENED 5->6 bits, see global_avg_pool.v
    wire [7:0] gap_data;

    cnn_gap global_avg_pool (

        .rst_n (rst_n),
        .clk   (clk),

        .gap_en   (gap_en),
        .gap_done (gap_done),

        .map_d_dout   (map_d_dout),   // reads D now, not C
        .map_d_rd_addr(map_d_rd_addr),
        .map_d_rd_en  (map_d_rd_en),

        .gap_addr (gap_addr),
        .gap_data (gap_data)

    );

    cnn_classifier fc_layer (

        .rst_n (rst_n),
        .clk   (clk),

        .fc_en   (fc_en),
        .fc_done (fc_done),

        .gap_addr (gap_addr),
        .gap_data (gap_data),

        .fc_addr     (fc_addr),
        .weight_data (weight_data),

        .class_result (class_result)

    );