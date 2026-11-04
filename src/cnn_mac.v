module cnn_mac
(
    input rst_n,
    input clk,
    input [2:0] conv_layer_sel, // WIDENED 2->3 bits: 5 states now (CONV1-4 + FC)
                                    // 3'b000 = CONV1
                                    // 3'b001 = CONV2
                                    // 3'b010 = CONV3
                                    // 3'b011 = CONV4
                                    // 3'b100 = FC

    input conv_en, //stay in idle till this is set

    output reg conv_done, //flag for when the conv layer is completed

    //========================================================
    // 96x96 BSRAM
    //========================================================

    input [7:0] resize_dout,   //input -> dout 96x96 [7:0]
    output [13:0] resize_addr, //output -> adb 96x96 [13:0]
    output reg resize_rd_en,       //output -> ceb 96x96

    //========================================================
    // FEATURE MAP BSRAM -- 4 buffers now:
    //   A: 24x24x12 = 6,912 B  (CONV1 out, 4x4 pool)
    //   B: 12x12x24 = 3,456 B  (CONV2 out, 2x2 pool)
    //   C: 6x6x48   = 1,728 B  (CONV3 out, 2x2 pool)
    //   D: 3x3x48   = 432 B    (CONV4 out, 2x2 pool -- NEW, GAP reads this)
    //
    // Unlike the original 3-layer design, mac_array now DOES read feature
    // map C (as CONV4's input) -- map_c_rd_en is a real output here, not
    // left unused.
    //========================================================

    output reg map_a_wr_en,
    output reg map_b_wr_en,
    output reg map_c_wr_en,
    output reg map_d_wr_en, // NEW

    output reg map_a_rd_en,
    output reg map_b_rd_en,
    output reg map_c_rd_en, // CHANGED: was `output map_c_rd_en` (unused wire)

    output reg [7:0] map_a_din,
    output reg [7:0] map_b_din,
    output reg [7:0] map_c_din,
    output reg [7:0] map_d_din, // NEW

    input [7:0] map_a_dout,
    input [7:0] map_b_dout,
    input [7:0] map_c_dout,

    output [12:0] map_a_wr_addr, // NARROWED 15->13 bits (6,912 deep)
    output [11:0] map_b_wr_addr, // NARROWED 14->12 bits (3,456 deep)
    output [10:0] map_c_wr_addr, // NARROWED 13->11 bits (1,728 deep)
    output [8:0]  map_d_wr_addr, // NEW (432 deep)

    output [12:0] map_a_rd_addr,
    output [11:0] map_b_rd_addr,
    output [10:0] map_c_rd_addr, // CHANGED: now actually driven, see above

    //========================================================
    // WEIGHT_ROM
    //========================================================

    input  [7:0]  weight_data,
    output [15:0] conv_addr, // WIDENED 13->16 bits (33,804 real conv weights,
                              // +1 padding word = 33,805-deep ROM -- see the
                              // conv_layer_base comment block below)

    input signed [7:0] bias_data,
    output       [7:0] bias_addr // WIDENED 6->8 bits (132 total biases)

);



reg signed [31:0] result [0:15];    // WIDENED 4->16 entries (max case: CONV1's 4x4=16 pool positions)
reg signed [31:0] pool_result;
reg signed [7:0] pixel_data_out;

//looping counters

reg [5:0] out_x;
reg [5:0] out_y;
reg [5:0] filter_index;

//x and y coordinates for each pool position (up to 16 now, was 4)

reg [6:0] pool_region_x [0:15]; // WIDENED 4->16 entries
reg [6:0] pool_region_y [0:15];
reg [3:0] pool_index;   // WIDENED 2->4 bits: counts 0-15 now (was 0-3)
reg [3:0] pool_k;       // NEW: pool window side length for the CURRENT layer
                        // (4 for CONV1, 2 for CONV2/3/4) -- everything
                        // pool-size-related derives from this

//9 MAC array variables

reg [6:0] mac_array_x [0:8];
reg [6:0] mac_array_y [0:8];
reg [3:0] mac_index;

reg [5:0] channel_index; // WIDENED 5->6 bits: max channel count is now 48 (CONV4), not 32

integer i, dx, dy; // loop variables, used in FSM_COORD's coordinate generation
                    // and FSM_POOL's max chain below

//Feature map A — 24x24x12 = 6,912 bytes  (Conv1+ReLU+Pool output, 4x4 pool)
//Feature map B — 12x12x24 = 3,456 bytes  (Conv2+ReLU+Pool output)
//Feature map C — 6x6x48   = 1,728 bytes  (Conv3+ReLU+Pool output)
//Feature map D — 3x3x48   = 432 bytes    (Conv4+ReLU+Pool output)


    //========================================================
    // FSM states
    //========================================================

    localparam FSM_IDLE  = 0;
    localparam FSM_COORD = 1;
    localparam FSM_ADDR  = 2;
    localparam FSM_MAC   = 3;
    localparam FSM_RELU  = 5;
    localparam FSM_POOL  = 6;
    localparam FSM_BOUND = 7;
    localparam FSM_WRITE = 8;
    localparam FSM_DONE  = 9;

    reg [3:0] state;


    //========================================================
    // Select CONV Layer Constants
    //========================================================

    reg       map_rd_en;
    reg       map_wr_en;
    reg [7:0] map_dout;
    reg [7:0] map_din;

    wire [13:0] map_rd_addr; // NARROWED 15->14 bits: resize (9,216 deep) is
                              // still the largest READ target across all
                              // layers, so this is sized to match
                              // resize_addr exactly
    reg [12:0] map_wr_addr;  // NARROWED 15->13 bits: map_a (6,912 deep) is
                              // now the largest WRITE target


    reg [6:0] frame;
    reg [5:0] num_filters;
    reg [6:0] in_width;

    reg [3:0] rescale_shift;

    reg [7:0] bias_layer_base; // WIDENED 6->8 bits: 132 total bias entries now
    reg signed [7:0] bias_reg;

    assign bias_addr = bias_layer_base + filter_index;

    // New base offsets (word counts = 9*Cin*Cout per layer):
    //   CONV1: base=0,     9*1*12=108 words
    //   CONV2: base=108,   9*12*24=2,592 words
    //   CONV3: base=2700,  9*24*48=10,368 words
    //   CONV4: base=13068, 9*48*48=20,736 words
    //   total = 33,804 real words, ROM is generated 1 word DEEPER (33,805)
    //   -- the address pipeline below transiently computes one address past
    //   each channel/filter's real 9 taps (an artifact of the 2-cycle
    //   capture delay, present in the original 3-layer design too). Every
    //   channel/filter except the very last one harmlessly lands on the
    //   next channel's/filter's real data; the last one has nothing real to
    //   land on, so it needs one extra padding word in the ROM instead
    //   (confirmed empirically: without it, simulation showed CONV4's
    //   entire last filter reading back as X). Real Gowin BRAM likely never
    //   showed this on the original design since physical memory doesn't
    //   go undefined past a nominal depth the way a simulation array does
    //   -- but there's no reason to rely on that rather than just padding.

    reg [15:0] conv_layer_base; // WIDENED 13->16 bits

    reg [5:0] channels_per_filter; // WIDENED 5->6 bits: max 48 now (CONV4)
    reg [5:0] num_channels;        // WIDENED 5->6 bits

    assign conv_addr = conv_layer_base + filter_index * (9 * channels_per_filter)
                        + channel_index * 9 + mac_index;

    always @(*) begin

        frame = 0;
        num_filters = 0;
        in_width = 0;
        num_channels = 0;
        conv_layer_base = 0;
        channels_per_filter = 0;
        rescale_shift = 4'd0;
        bias_layer_base = 8'd0;
        pool_k = 4'd2; // safe default, every real branch below overrides it

        resize_rd_en = 1'b0;
        map_a_wr_en  = 1'b0;
        map_b_wr_en  = 1'b0;
        map_c_wr_en  = 1'b0;
        map_d_wr_en  = 1'b0;
        map_a_rd_en  = 1'b0;
        map_b_rd_en  = 1'b0;
        map_c_rd_en  = 1'b0;
        map_din      = 8'd0;
        map_a_din    = 8'd0;
        map_b_din    = 8'd0;
        map_c_din    = 8'd0;
        map_d_din    = 8'd0;

        case (conv_layer_sel)

            3'b000: begin //96x96 -> 24x24x12 (4x4 pool)

                frame = 24;
                num_filters = 12;
                in_width = 96;
                num_channels = 1;
                pool_k = 4'd4;

                resize_rd_en = map_rd_en; //96x96    rd
                map_a_wr_en = map_wr_en;  //24x24x12 wr
                map_din   = resize_dout;
                map_a_din = map_dout;

                conv_layer_base = 0;
                channels_per_filter = 1;
                rescale_shift = 4'd3; //calibrated from trained weights CONV1
                bias_layer_base = 8'd0; //filters 0-11

            end

            3'b001: begin //24x24x12 -> 12x12x24

                frame = 12;
                num_filters = 24;
                in_width = 24;
                num_channels = 12;
                pool_k = 4'd2;

                map_a_rd_en = map_rd_en;
                map_b_wr_en = map_wr_en;
                map_din   = map_a_dout;
                map_b_din = map_dout;

                conv_layer_base = 108;
                channels_per_filter = 12;
                rescale_shift = 4'd5; //calibrated from trained weights CONV2
                bias_layer_base = 8'd12; //filters 0-23

            end

            3'b010: begin //12x12x24 -> 6x6x48

                frame = 6;
                num_filters = 48;
                in_width = 12;
                num_channels = 24;
                pool_k = 4'd2;

                map_b_rd_en = map_rd_en;
                map_c_wr_en = map_wr_en;
                map_din   = map_b_dout;
                map_c_din = map_dout;

                conv_layer_base = 2700;
                channels_per_filter = 24;
                rescale_shift = 4'd5; //calibrated from trained weights CONV3
                bias_layer_base = 8'd36; //filters 0-47

            end

            3'b011: begin //6x6x48 -> 3x3x48 (NEW layer)

                frame = 3;
                num_filters = 48;
                in_width = 6;
                num_channels = 48;
                pool_k = 4'd2;

                map_c_rd_en = map_rd_en; // mac_array reads C now, unlike the
                                          // original 3-layer design
                map_d_wr_en = map_wr_en;
                map_din   = map_c_dout;
                map_d_din = map_dout;

                conv_layer_base = 13068;
                channels_per_filter = 48;
                rescale_shift = 4'd6; //calibrated from trained weights CONV4
                bias_layer_base = 8'd84; //filters 0-47

            end

            default: begin
                // FC layer (3'b100) and any unused encoding
            end

        endcase

    end

    //tie addr_map outputs to the generic map_addr variables

    assign resize_addr = map_rd_addr;
    assign map_a_rd_addr  = map_rd_addr[12:0];
    assign map_b_rd_addr  = map_rd_addr[11:0];
    assign map_c_rd_addr  = map_rd_addr[10:0];

    assign map_a_wr_addr  = map_wr_addr;
    assign map_b_wr_addr  = map_wr_addr[11:0];
    assign map_c_wr_addr  = map_wr_addr[10:0];
    assign map_d_wr_addr  = map_wr_addr[8:0];

    wire signed [31:0] scaled_result = pool_result >>> rescale_shift;

    //========================================================
    // 9 MAC Pixel Locations -- unchanged, always a 3x3 kernel regardless
    // of pool size or channel count
    //========================================================

    reg [1:0] fr, fc;

    always @(*) begin

        case (mac_index)

            0: begin fr=0; fc=0; end
            1: begin fr=0; fc=1; end
            2: begin fr=0; fc=2; end
            3: begin fr=1; fc=0; end
            4: begin fr=1; fc=1; end
            5: begin fr=1; fc=2; end
            6: begin fr=2; fc=0; end
            7: begin fr=2; fc=1; end
            8: begin fr=2; fc=2; end
            default: begin fr=0; fc=0; end

        endcase
    end

    wire signed [7:0] mac_x = pool_region_x[pool_index] + fc - 1;
    wire signed [7:0] mac_y = pool_region_y[pool_index] + fr - 1;

    wire mac_valid = (mac_x >= 0) && (mac_x < in_width) && (mac_y >= 0) && (mac_y < in_width);
    assign map_rd_addr = mac_valid ? (channel_index * in_width * in_width + mac_y * in_width + mac_x) : 14'd0;

    reg mac_valid_stage1, mac_valid_stage2;

    //========================================================
    // Main FSM
    //========================================================

    always @(posedge clk or negedge rst_n) begin

        if(!rst_n) begin

            state <= FSM_IDLE;

            out_x <= 0;
            out_y <= 0;
            filter_index <= 0;

            pool_index <= 0;
            mac_index <= 0;
            channel_index <= 0;

            for (i = 0; i < 16; i = i + 1) begin
                pool_region_x[i] <= 0;
                pool_region_y[i] <= 0;
                result[i] <= 0;
            end

            mac_array_x[0] <= 0;
            mac_array_x[1] <= 0;
            mac_array_x[2] <= 0;
            mac_array_x[3] <= 0;
            mac_array_x[4] <= 0;
            mac_array_x[5] <= 0;
            mac_array_x[6] <= 0;
            mac_array_x[7] <= 0;
            mac_array_x[8] <= 0;

            mac_array_y[0] <= 0;
            mac_array_y[1] <= 0;
            mac_array_y[2] <= 0;
            mac_array_y[3] <= 0;
            mac_array_y[4] <= 0;
            mac_array_y[5] <= 0;
            mac_array_y[6] <= 0;
            mac_array_y[7] <= 0;
            mac_array_y[8] <= 0;

            conv_done <= 0;

            mac_valid_stage1 <= 1'b0;
            mac_valid_stage2 <= 1'b0;

            acc_in_en <= 0;
            bias_reg <= 0;
            pool_result <= 0;
            pixel_data_out <= 0;

        end else begin

            case(state)

                FSM_IDLE: begin

                    conv_done <= 1'b0;

                    if (conv_en == 1'b1) begin

                        out_x <= 0;
                        out_y <= 0;
                        filter_index <= 0;

                        state <= FSM_COORD;

                    end

                end

                //============================================
                //
                //============================================
                FSM_COORD: begin

                    // Generate up to pool_k*pool_k sub-window coordinates.
                    // Written as a fixed 4x4 (16-iteration) loop gated by
                    // "dx < pool_k && dy < pool_k" instead of a loop bounded
                    // by pool_k directly, since pool_k is a runtime SIGNAL
                    // (varies by layer) and Verilog for-loop bounds must be
                    // fixed at synthesis time. For CONV1 (pool_k=4) all 16
                    // iterations fire; for CONV2/3/4 (pool_k=2) only the
                    // dx<2,dy<2 quarter (4 of the 16) fire, matching the
                    // original file's exact 2x2 pattern for those layers.
                    for (dy = 0; dy < 4; dy = dy + 1) begin
                        for (dx = 0; dx < 4; dx = dx + 1) begin
                            if (dx < pool_k && dy < pool_k) begin
                                pool_region_x[dy * pool_k + dx] <= out_x * pool_k + dx;
                                pool_region_y[dy * pool_k + dx] <= out_y * pool_k + dy;
                            end
                        end
                    end

                    for (i = 0; i < 16; i = i + 1) begin
                        result[i] <= 0;
                    end

                    mac_index <= 0;
                    channel_index <= 0;

                    state <= FSM_ADDR;

                end

                //============================================
                //
                //============================================
                FSM_ADDR: begin

                    mac_valid_stage1 <= mac_valid;
                    mac_valid_stage2 <= mac_valid_stage1;

                    if (mac_index > 1) begin

                        mac_pixel_data[mac_index - 2] <= mac_valid_stage2 ? map_din : 8'sd0;
                        mac_weight[mac_index - 2] <= weight_data;

                    end

                    if (mac_index == 4'd2) begin
                        bias_reg <= bias_data;
                    end

                    if (mac_index < 10) begin

                        map_rd_en <= 1'b1;
                        mac_index <= mac_index + 1;

                    end else begin

                        state <= FSM_MAC;

                    end

                end

                //============================================
                //
                //============================================
                FSM_MAC: begin

                    acc_in_en <= 1'b1;

                    if(acc_out_en) begin

                        result[pool_index] <= result[pool_index] + acc_temp;
                        acc_in_en <= 1'b0;

                        if(channel_index == num_channels - 1) begin

                            if(pool_index == (pool_k * pool_k - 1)) begin
                                // WAS: if(pool_index == 3) -- now the last
                                // valid pool position depends on pool_k
                                // (15 for CONV1's 4x4=16 positions, 3 for
                                // the others' 2x2=4 positions)

                                pool_index <= 0;
                                state <= FSM_RELU;

                            end else begin

                                pool_index <= pool_index + 1'b1;
                                channel_index <= 0;
                                mac_index <= 0;
                                state <= FSM_ADDR;

                            end

                        end else begin

                            channel_index <= channel_index + 1'b1;
                            mac_index <= 0;
                            state <= FSM_ADDR;

                        end

                    end


                end

                //============================================
                // ReLU -- generalized from 4 explicit lines to a loop over
                // up to 16 positions, gated by pool_k*pool_k same as above
                //============================================
                FSM_RELU: begin

                    for (i = 0; i < 16; i = i + 1) begin
                        if (i < pool_k * pool_k) begin
                            result[i] <= (result[i] + bias_reg) < 32'sd0 ? 32'sd0 : (result[i] + bias_reg);
                        end
                    end

                    state <= FSM_POOL;

                end

                //============================================
                // Max-pool -- generalized from a fixed 4-way max to a
                // fixed-16-iteration loop gated by pool_k*pool_k, same
                // pattern as FSM_RELU above. Blocking assignments kept
                // (same reasoning as the original file: each comparison
                // must see the previous comparison's result within this
                // same cycle).
                //============================================
                FSM_POOL: begin

                    pool_result = result[0];

                    for (i = 1; i < 16; i = i + 1) begin
                        if (i < pool_k * pool_k && result[i] > pool_result) begin
                            pool_result = result[i];
                        end
                    end

                    state <= FSM_BOUND;

                end

                //============================================
                //Saturate or truncate pool_result to ensure its within 8 bits
                //============================================
                FSM_BOUND: begin

                    if(scaled_result > 127) begin

                        pixel_data_out <= 127;

                    end else if(scaled_result < -128) begin

                        pixel_data_out <= -128;

                    end else begin

                        pixel_data_out <= scaled_result[7:0];

                    end

                    state <= FSM_WRITE;

                end

                //============================================
                //
                //============================================
                FSM_WRITE: begin

                    map_wr_addr <= filter_index * (frame*frame) + out_y * frame + out_x;

                    map_wr_en <= 1'b1;
                    map_dout <= pixel_data_out;

                    state <= FSM_DONE;

                end

                //============================================
                //
                //============================================
                FSM_DONE: begin

                    map_wr_en <= 1'b0;

                    if (out_x < frame - 1) begin

                        out_x <= out_x + 1;
                        state <= FSM_COORD;

                    end else if (out_y < frame - 1) begin

                        out_x <= 0;
                        out_y <= out_y + 1;
                        state <= FSM_COORD;

                    end else if (filter_index < num_filters - 1) begin

                        out_x <= 0;
                        out_y <= 0;
                        filter_index <= filter_index + 1;
                        state <= FSM_COORD;

                    end else begin

                        conv_done <= 1'b1;
                        state <= FSM_IDLE;

                    end

                end


            endcase

        end

    end

    //========================================================
    // 9 MACs ACC Calculation -- completely unchanged: always exactly a
    // 3x3 kernel (9 taps) regardless of pool size or channel count
    //========================================================

reg acc_in_en;
wire acc_out_en;

wire signed [71:0] pixel_bus;
wire signed [71:0] weight_bus;

reg signed [7:0] mac_pixel_data  [0:8];
reg signed [7:0] mac_weight [0:8];

wire signed [31:0] acc_temp;

assign pixel_bus = {mac_pixel_data[0], mac_pixel_data[1], mac_pixel_data[2],
                    mac_pixel_data[3], mac_pixel_data[4], mac_pixel_data[5],
                    mac_pixel_data[6], mac_pixel_data[7], mac_pixel_data[8]};

assign weight_bus = {mac_weight[0], mac_weight[1], mac_weight[2],
                     mac_weight[3], mac_weight[4], mac_weight[5],
                     mac_weight[6], mac_weight[7], mac_weight[8]};

cnn_acc #(.DATA_W(8), .ACC_W (32)) conv_core_acc (

    .clk        (clk),
    .rst_n      (rst_n),
    .acc_in_en  (acc_in_en),

    .window_in  (pixel_bus),
    .weight_in  (weight_bus),

    .acc_out_en (acc_out_en),
    .acc_out    (acc_temp)
);



endmodule
