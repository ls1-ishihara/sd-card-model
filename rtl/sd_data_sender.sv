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
    input  logic        bus_width_4bit,
    output logic [3:0]  sd_dat_out,
    output logic [3:0]  sd_dat_oe,
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
    logic [15:0] bit_count;
    logic [15:0] payload_clocks;

    always_comb begin
        payload_clocks = bus_width_4bit ? BLOCK_SIZE_BYTES * 2 : BLOCK_SIZE_BYTES * 8;
        if (bit_count >= 16'd1 && bit_count <= payload_clocks)
            memory_offset = (bit_count - 1'b1) / (bus_width_4bit ? 2 : 8);
        else
            memory_offset = '0;
    end

    always_ff @(posedge sd_clk or negedge sd_reset_n) begin
        if (!sd_reset_n) begin
            state <= DATA_IDLE;
            delay_count <= '0;
            bit_count <= '0;
            sd_dat_out <= 4'b1111;
            sd_dat_oe <= 4'b0000;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                DATA_IDLE: begin
                    sd_dat_oe <= 4'b0000;
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
                    sd_dat_oe <= bus_width_4bit ? 4'b1111 : 4'b0001;
                    if (bit_count == 16'd0) begin
                        sd_dat_out <= 4'b0000;
                    end else if (bit_count <= payload_clocks) begin
                        if (bus_width_4bit)
                            sd_dat_out <= (bit_count[0] == 1'b1) ? memory_data[7:4] : memory_data[3:0];
                        else begin
                            sd_dat_out <= 4'b0000;
                            sd_dat_out[0] <= memory_data[7 - ((bit_count - 1'b1) % 8)];
                        end
                    end else if (bit_count <= payload_clocks + 16) begin
                        sd_dat_out <= 4'b0000;
                    end else begin
                        sd_dat_out <= bus_width_4bit ? 4'b1111 : 4'b0001;
                    end

                    if (bit_count == payload_clocks + 17) begin
                        state <= DATA_RELEASE;
                    end else begin
                        bit_count <= bit_count + 1'b1;
                    end
                end
                DATA_RELEASE: begin
                    sd_dat_oe <= 4'b0000;
                    sd_dat_out <= 4'b1111;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= DATA_IDLE;
                end
                default: state <= DATA_IDLE;
            endcase
        end
    end
endmodule