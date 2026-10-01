module sd_data_sender #(
    parameter integer RESPONSE_DELAY = 8,
    parameter integer BLOCK_SIZE_BYTES = 512
) (
    input  logic        sd_clk,
    input  logic        sd_reset_n,
    input  logic        start,
    input  logic [31:0] block_address,
    input  logic [7:0]  memory_data,
    output logic [31:0] memory_offset,
    output logic        sd_dat0_out,
    output logic        sd_dat0_oe,
    output logic        busy,
    output logic        done
);
    typedef enum logic [2:0] {
        DATA_IDLE,
        DATA_WAIT,
        DATA_SEND,
        DATA_RELEASE
    } data_state_t;

    data_state_t state;
    logic [15:0] delay_count;
    logic [12:0] bit_count;

    always_comb begin
        if (bit_count >= 13'd1 && bit_count <= BLOCK_SIZE_BYTES * 8)
            memory_offset = (bit_count - 1'b1) / 8;
        else
            memory_offset = '0;
    end

    always_ff @(posedge sd_clk or negedge sd_reset_n) begin
        if (!sd_reset_n) begin
            state <= DATA_IDLE;
            delay_count <= '0;
            bit_count <= '0;
            sd_dat0_out <= 1'b1;
            sd_dat0_oe <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                DATA_IDLE: begin
                    sd_dat0_oe <= 1'b0;
                    busy <= 1'b0;
                    if (start) begin
                        delay_count <= RESPONSE_DELAY > 5 ? RESPONSE_DELAY - 5 : 0;
                        bit_count <= '0;
                        busy <= 1'b1;
                        state <= DATA_WAIT;
                    end
                end
                DATA_WAIT: begin
                    if (delay_count + 1'b1 >= RESPONSE_DELAY) begin
                        bit_count <= '0;
                        state <= DATA_SEND;
                    end else begin
                        delay_count <= delay_count + 1'b1;
                    end
                end
                DATA_SEND: begin
                    sd_dat0_oe <= 1'b1;
                    if (bit_count == 13'd0) begin
                        sd_dat0_out <= 1'b0;
                    end else if (bit_count <= BLOCK_SIZE_BYTES * 8) begin
                        sd_dat0_out <= memory_data[7 - ((bit_count - 1'b1) % 8)];
                    end else if (bit_count <= BLOCK_SIZE_BYTES * 8 + 16) begin
                        sd_dat0_out <= 1'b0;
                    end else begin
                        sd_dat0_out <= 1'b1;
                    end

                    if (bit_count == BLOCK_SIZE_BYTES * 8 + 17) begin
                        state <= DATA_RELEASE;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end
                DATA_RELEASE: begin
                    sd_dat0_oe <= 1'b0;
                    sd_dat0_out <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= DATA_IDLE;
                end
                default: state <= DATA_IDLE;
            endcase
        end
    end
endmodule