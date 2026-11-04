module dvp_capture
(
    input rst_n,
    input pclk,
    input[7:0] input_data,
    input de_i, //HREF or valid data

    output reg[7:0] y_data,
    output reg[7:0] cbcr_data, //alternating bytes U/V

//    output reg[15:0] out_data,

    output reg      hblank,
    output reg      de_o
    
);
//get 16 bits of data and then separate into y_data = Y and crcb_data = UV

reg[7:0] previous_byte;
reg byte_toggle;

//record incoming byte
always@(posedge pclk or negedge rst_n)
begin
    if(!rst_n)
        previous_byte <= 8'd0;
    else
        previous_byte <= input_data;
end

//as long as we have posedge of pclk and data is valid -> toggle
always@(posedge pclk or negedge rst_n)
begin
    if(!rst_n)
        byte_toggle <= 0;
    else if(de_i)
        byte_toggle <= ~byte_toggle;
    else
        byte_toggle <= 0;
end

//as long as its not on reset -> if data is valid and byte has toggled (which means we have 2 bytes)
always@(posedge pclk or negedge rst_n)
begin
    if(!rst_n)
        de_o <= 1'b0;
    else if(de_i && byte_toggle)
        de_o <= 1'b1;
    else
        de_o <= 1'b0;
end

always@(posedge pclk or negedge rst_n)
begin
    if(!rst_n)
        hblank <= 1'b0;
    else
        hblank <= de_i;
end

//output y_data = Y and crcb_data = U or V otherwise no change
always@(posedge pclk or negedge rst_n)
begin  
    if(!rst_n) begin

        y_data <= 8'd0;
        cbcr_data <= 8'd0;

//        out_data <= 16'd0;

    end else if(de_i && byte_toggle) begin

        y_data <= previous_byte;
        cbcr_data <= input_data;
//        y_data <= 8'hFF;
//        cbcr_data <= 8'hFF;
        
//        out_data <= {input_data, previous_byte};

    end
end


endmodule