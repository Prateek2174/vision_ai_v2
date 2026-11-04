module cnn_top
(
    input rst_n,
    input pclk,
    input frame_ready, // pulses/goes high once a full 96x96 frame has been
                        // written into the resize BSRAM by the UART
                        // byte-assembly logic. Unchanged from the original
                        // design -- this signal's meaning has nothing to do
                        // with channel/layer counts.

    output reg conv_en,
    output reg pool_en,
    output reg gap_en,
    output reg fc_en,
    output reg uart_en, // vestigial -- see FSM_FC comment below. Always 0.

    input conv_done,
    input pool_done,
    input gap_done,
    input fc_done,
    input uart_done, // vestigial, ignored -- see FSM_FC comment below.

    output reg [2:0] conv_layer_sel, // WIDENED 2->3 bits -- see weight_rom.v:
                                      // 5 states now (CONV1-4 + FC) don't fit
                                      // in 2 bits anymore

    output busy // high whenever a classification is in progress -- see
                // original file's comment, unchanged reasoning

);

    reg frame_ready_prev;

    always @(posedge pclk or negedge rst_n) begin

        if(!rst_n) begin

            frame_ready_prev <= 1'b0;

        end else begin
            frame_ready_prev <= frame_ready;
        end

    end

    wire frame_start = ~frame_ready_prev & frame_ready; //rising edge

    //========================================================
    // FSM states -- added FSM_CONV4 between FSM_CONV3 and FSM_GAP for the
    // small architecture's 4th conv layer
    //========================================================

    localparam FSM_IDLE  = 0;
    localparam FSM_CONV1 = 1;
    localparam FSM_CONV2 = 2;
    localparam FSM_CONV3 = 3;
    localparam FSM_CONV4 = 4;
    localparam FSM_GAP   = 5;
    localparam FSM_FC    = 6;

    reg [3:0] state;

    assign busy = (state != FSM_IDLE);

    //========================================================
    // Main FSM
    //========================================================

    always @(posedge pclk or negedge rst_n) begin

        if(!rst_n) begin

            state <= FSM_IDLE;

            conv_en <= 1'b0;
            pool_en <= 1'b0;
            gap_en  <= 1'b0;
            fc_en   <= 1'b0;
            uart_en <= 1'b0;

            conv_layer_sel <= 3'b000;

        end else begin

            case(state)

                FSM_IDLE: begin

                    if (frame_start) begin

                        state <= FSM_CONV1;

                    end

                end

                FSM_CONV1: begin

                    conv_layer_sel <= 3'b000; //CONV1 weights
                    conv_en        <= 1'b1;

                    if(conv_done) begin

                        conv_en <= 1'b0;
                        state <= FSM_CONV2;

                    end

                end

                FSM_CONV2: begin

                    conv_layer_sel <= 3'b001; //CONV2 weights
                    conv_en        <= 1'b1;

                    if(conv_done) begin

                        conv_en <= 1'b0;
                        state <= FSM_CONV3;

                    end

                end

                FSM_CONV3: begin

                    conv_layer_sel <= 3'b010; //CONV3 weights
                    conv_en        <= 1'b1;

                    if(conv_done) begin

                        conv_en <= 1'b0;
                        state <= FSM_CONV4;

                    end

                end

                FSM_CONV4: begin

                    conv_layer_sel <= 3'b011; //CONV4 weights
                    conv_en        <= 1'b1;

                    if(conv_done) begin

                        conv_en <= 1'b0;
                        state <= FSM_GAP;

                    end

                end

                FSM_GAP: begin

                    gap_en <= 1'b1;

                    if(gap_done) begin

                        gap_en <= 1'b0;
                        state <= FSM_FC;

                    end

                end

                FSM_FC: begin

                    conv_layer_sel <= 3'b100; //FC weights
                    fc_en <= 1'b1;

                    if(fc_done) begin

                        // Same reasoning as the original file: no UART TX
                        // handshake needed, LED decoder reads class_result
                        // combinationally. Go straight back to FSM_IDLE.
                        fc_en <= 1'b0;
                        state <= FSM_IDLE;

                    end

                end

            endcase

        end

    end



endmodule
