module sd_response_generator (
    input  logic         sd_clk,
    input  logic         sd_reset_n,
    input  logic         response_start,
    input  logic [135:0] response_frame,
    input  logic [7:0]   response_length,
    output logic         sd_cmd_out,
    output logic         sd_cmd_oe,
    output logic         response_busy,
    output logic         response_done
);
    logic [135:0] frame_shift;
    logic [7:0] bit_count;
    logic [7:0] frame_length;

    always_ff @(posedge sd_clk or negedge sd_reset_n) begin
        if (!sd_reset_n) begin
            frame_shift <= '0;
            bit_count <= '0;
            frame_length <= '0;
            sd_cmd_out <= 1'b1;
            sd_cmd_oe <= 1'b0;
            response_busy <= 1'b0;
            response_done <= 1'b0;
        end else begin
            response_done <= 1'b0;
            if (!response_busy) begin
                sd_cmd_oe <= 1'b0;
                if (response_start) begin
                    frame_shift <= response_frame;
                    frame_length <= response_length;
                    bit_count <= '0;
                    response_busy <= 1'b1;
                end
            end else begin
                sd_cmd_oe <= 1'b1;
                sd_cmd_out <= frame_shift[135];
                frame_shift <= {frame_shift[134:0], 1'b0};
                if (bit_count + 1'b1 >= frame_length) begin
                    response_busy <= 1'b0;
                    response_done <= 1'b1;
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end
endmodule