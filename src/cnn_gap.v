module cnn_gap //Global Average Pool
(
    input  rst_n,
    input  clk,

    input  gap_en,       // start signal from cnn_top
    output reg gap_done, // done signal to cnn_top

    //========================================================
    // FEATURE MAP D BSRAM (3x3x48) -- output of the 4th conv layer.
    // Small architecture: conv1 uses a 4x4 pool (not 2x2), so the spatial
    // progression from 96x96 is 96->24->12->6->3, landing on 3x3x48 here
    // instead of the original 3-layer design's 12x12x32 feature map C.
    //========================================================

    input  [7:0] map_d_dout,      // input <- dout MAP D
    output [8:0] map_d_rd_addr,   // output -> adb MAP D (9*48=432 real
                                   // addresses, but generate the IP core 1
                                   // word DEEPER at 433 -- pixel_index's
                                   // pipeline-latency overshoot (same
                                   // pattern as mac_array.v's conv_addr and
                                   // classifier.v's fc_addr) transiently
                                   // reads channel_index*9+9=432 for the
                                   // very last channel, one past the real
                                   // range. Confirmed empirically: without
                                   // this, simulation showed the last
                                   // channel's gap_result reading back as X.
                                   // Still fits in 9 bits either way.
    output reg map_d_rd_en,       // output -> ceb MAP D

    //========================================================
    // GAP RESULT READ INTERFACE (for classifier.v)
    //========================================================

    input  [5:0] gap_addr,   // classifier requests channel 0-47
    output [7:0] gap_data    // averaged value for that channel

);

    localparam CH_SIZE = 9;    // 3*3 pixels per channel (was 144 for 12x12)
    localparam NUM_CH  = 48;   // channels in feature map D (was 32)

    reg [5:0] channel_index;   // 0-47
    reg [7:0] pixel_index;     // 0-8 (8 bits is more than enough, kept for
                                // consistency with the original file rather
                                // than trimming to the exact minimum)

    reg signed [17:0] acc;     // running sum, max 9*127=1143 (was 144*127=18288
                                // -- kept at 18 bits, plenty of headroom either way)

    reg signed [7:0] gap_result [0:47]; // 48 averaged int8 values

    assign gap_data = gap_result[gap_addr];

    //constantly generate the read address for the pixel we're gathering
    //(same pattern as mac_array's map_rd_addr -- combinational, driven every cycle)
    assign map_d_rd_addr = channel_index * CH_SIZE + pixel_index;

    //========================================================
    // FSM states
    //========================================================

    localparam FSM_IDLE    = 0;
    localparam FSM_GATHER  = 1; // accumulate one channel's 9 pixels
    localparam FSM_DIVIDE  = 2; // approximate divide, store result
    localparam FSM_NEXT    = 3; // advance to next channel or finish

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= FSM_IDLE;
            channel_index <= 0;
            pixel_index <= 0;
            acc <= 0;
            gap_done <= 0;
            map_d_rd_en <= 0;

        end else begin

            case (state)

                FSM_IDLE: begin

                    gap_done <= 0;

                    if (gap_en) begin
                        channel_index <= 0;
                        pixel_index <= 0;
                        acc <= 0;
                        state <= FSM_GATHER;
                    end

                end

                FSM_GATHER: begin

                    // Same 2-cycle BSRAM latency skip as the original file --
                    // this is a hardware property of the feature-map BRAM
                    // primitive itself, not something that depends on
                    // channel count or spatial size, so it's unchanged here.

                    if (pixel_index > 1) begin
                        acc <= acc + map_d_dout;
                    end

                    if (pixel_index < CH_SIZE + 1) begin
                        map_d_rd_en <= 1'b1;
                        pixel_index <= pixel_index + 1;
                    end else begin
                        state <= FSM_DIVIDE;
                    end

                end

                FSM_DIVIDE: begin

                    //approximate divide by 128 via right-shift by 7 -- kept
                    //identical to the original file: this matches the
                    //Python model's fixed acc/128.0 normalization, which is
                    //a constant regardless of how many pixels are summed
                    //(see conversation notes -- confirmed this doesn't need
                    //to track the actual CH_SIZE).

                    state <= FSM_NEXT;

                    if (acc >>> 7 > 127) begin

                        gap_result[channel_index] <= 127;

                    end else begin

                        gap_result[channel_index] <= acc >>> 7;

                    end

                end

                FSM_NEXT: begin

                    if (channel_index == NUM_CH - 1) begin
                        gap_done <= 1'b1;
                        state <= FSM_IDLE;
                    end else begin
                        channel_index <= channel_index + 1;
                        pixel_index <= 0;
                        acc <= 0;
                        state <= FSM_GATHER;
                    end

                end

            endcase

        end

    end

endmodule
