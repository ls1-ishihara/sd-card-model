module sd_command_receiver (
    input  logic       sd_clk,
    input  logic       sd_reset_n,
    input  logic       card_cmd_oe,
    input  wire        sd_cmd_in,
    output logic       command_valid,
    output logic [5:0] command_index,
    output logic [31:0] command_argument
);
    logic [47:0] command_shift;
    logic [5:0] bit_count;
    logic receiving;

    always_ff @(posedge sd_clk or negedge sd_reset_n) begin
        if (!sd_reset_n) begin
            command_shift <= '0;
            bit_count <= '0;
            receiving <= 1'b0;
            command_valid <= 1'b0;
            command_index <= '0;
            command_argument <= '0;
        end else begin
            command_valid <= 1'b0;
            if (!receiving) begin
                if (!card_cmd_oe && sd_cmd_in === 1'b0) begin
                    command_shift <= {47'b0, sd_cmd_in};
                    bit_count <= 6'd1;
                    receiving <= 1'b1;
                end
            end else begin
                command_shift <= {command_shift[46:0], sd_cmd_in};
                if (bit_count == 6'd47) begin
                    command_index <= command_shift[44:39];
                    command_argument <= command_shift[38:7];
                    command_valid <= 1'b1;
                    bit_count <= '0;
                    receiving <= 1'b0;
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end
endmodule