module cnn_classifier
(
    input  rst_n,
    input  clk,

    input  fc_en,        // start signal from cnn_top
    output reg fc_done,  // done signal to cnn_top

    //========================================================
    // GLOBAL_AVG_POOL READ INTERFACE
    //========================================================

    output [5:0] gap_addr,  // request channel 0-47 (was 0-31 -- small arch's
                             // conv4 has 48 channels, not 32)
    input  [7:0] gap_data,  // averaged value for that channel (combinational, no latency)

    //========================================================
    // WEIGHT_ROM READ INTERFACE (FC weights)
    //========================================================

    output [6:0] fc_addr,     // weight address, real range 0-95 (48 inputs *
                               // 2 outputs, was 0-191 for 32*6) -- fc_rom is
                               // generated 102 DEEP (not 96): in_idx's FSM
                               // loop transiently reaches NUM_IN+2=50 (the
                               // value that fails its own "keep going"
                               // check), giving fc_addr=50*2+1=101 for the
                               // last output neuron. Confirmed empirically
                               // via simulation, not just derived -- an
                               // earlier estimate of +1 padding undercounted
                               // this same way conv_addr's first estimate did.
    input  [7:0] weight_data, // weight value (pROM, 3-cycle latency --
                               // same real Gowin BRAM/pROM latency as the
                               // original 6-class classifier.v; the pipeline
                               // depth below is unchanged from that proven
                               // design)

    //========================================================
    // RESULT
    //========================================================

    output reg class_result  // 0 = no person, 1 = person (was 3-bit 0-5)

);

    localparam NUM_IN  = 48;  // inputs from GAP (was 32 -- small arch's conv4
                               // output channel count)
    localparam NUM_OUT = 2;   // person / no-person (was 6 finger-count classes)

    reg [5:0] in_idx;    // 0-47, counts up to NUM_IN+2=50 before wrapping --
                         // still fits comfortably in 6 bits (max 63), same
                         // headroom reasoning as the original file
    reg out_idx;         // 0-1 (was 3 bits for 0-5)

    reg signed [7:0]  weight_reg;
    reg signed [7:0]  gap_reg;
    reg signed [7:0]  gap_reg_stage1, gap_reg_stage2;
    // Pipeline depth (3 stages) is UNCHANGED from the original classifier.v --
    // this was determined empirically against real Gowin pROM/BRAM latency,
    // which is a hardware property of the memory primitive itself, not
    // something that depends on channel count or class count. No reason to
    // re-derive it for this architecture.

    reg signed [31:0] acc;
    reg signed [31:0] fc_result [0:1];        // 2 output scores (was 6)

    //constantly generate the read addresses for the tap we're gathering
    //(same pattern as mac_array/global_avg_pool -- combinational, driven every cycle)
    //weight_rom layout: weight[in_idx][out_idx] stored in_idx-major, out_idx-minor
    assign fc_addr  = in_idx * NUM_OUT + out_idx;
    assign gap_addr = in_idx;

    //========================================================
    // FSM states
    //========================================================

    localparam FSM_IDLE    = 0;
    localparam FSM_GATHER  = 1; // accumulate one output neuron's 48-tap dot product
    localparam FSM_NEXT    = 2; // advance to next output neuron or move to argmax
    localparam FSM_ARGMAX  = 3; // compare both scores, pick the winner

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= FSM_IDLE;
            in_idx <= 0;
            out_idx <= 0;
            acc <= 0;
            fc_done <= 0;
            class_result <= 0;

        end else begin

            case (state)

                FSM_IDLE: begin

                    fc_done <= 0;

                    if (fc_en) begin
                        out_idx <= 0;
                        in_idx <= 0;
                        acc <= 0;
                        state <= FSM_GATHER;
                    end

                end

                FSM_GATHER: begin

                    // Same 3-cycle skip as the original classifier.v -- see
                    // gap_reg_stage declaration comment above for why.

                    if (in_idx > 2) begin
                        acc <= acc + (weight_reg * gap_reg);
                    end

                    weight_reg     <= weight_data;
                    gap_reg        <= gap_reg_stage2;
                    gap_reg_stage2 <= gap_reg_stage1;
                    gap_reg_stage1 <= gap_data;

                    if (in_idx < NUM_IN + 2) begin
                        in_idx <= in_idx + 1;
                    end else begin
                        state <= FSM_NEXT;
                    end

                end

                FSM_NEXT: begin

                    fc_result[out_idx] <= acc;

                    if (out_idx == NUM_OUT - 1) begin
                        state <= FSM_ARGMAX;
                    end else begin
                        out_idx <= out_idx + 1;
                        in_idx <= 0;
                        acc <= 0;
                        state <= FSM_GATHER;
                    end

                end

                FSM_ARGMAX: begin

                    // Only 2 classes now, so this collapses to a single
                    // comparison instead of the original's 5-way chain --
                    // same blocking-assignment reasoning still applies (not
                    // that it matters with only one comparison), kept as a
                    // registered output for a clean single-cycle result.

                    class_result <= (fc_result[1] > fc_result[0]) ? 1'b1 : 1'b0;

                    fc_done <= 1'b1;
                    state <= FSM_IDLE;

                end

            endcase

        end

    end

endmodule
