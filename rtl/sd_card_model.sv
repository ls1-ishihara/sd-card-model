module sd_card_model #(
    parameter IMAGE_FILE = "boot.mem",
    parameter integer IMAGE_SIZE_BYTES = 32 * 1024 * 1024,
    parameter integer BLOCK_SIZE_BYTES = 512,
    parameter integer RESPONSE_DELAY = 8
) (
    input  logic sd_reset_n,
    input  logic sd_clk,
    inout  wire  sd_cmd,
`ifdef SD_CARD_MODEL_4BIT
    inout  wire [3:0] sd_dat
`else
    inout  wire  sd_dat0
`endif
);
    localparam logic [2:0] CARD_IDLE = 3'd0;
    localparam logic [2:0] CARD_READY = 3'd1;
    localparam logic [2:0] CARD_IDENT = 3'd2;
    localparam logic [2:0] CARD_STANDBY = 3'd3;
    localparam logic [2:0] CARD_TRANSFER = 3'd4;

    localparam logic [3:0] CMD_UNKNOWN = 4'd0;
    localparam logic [3:0] CMD_GO_IDLE = 4'd1;
    localparam logic [3:0] CMD_SEND_IF_COND = 4'd2;
    localparam logic [3:0] CMD_APP = 4'd3;
    localparam logic [3:0] CMD_OP_COND = 4'd4;
    localparam logic [3:0] CMD_ALL_CID = 4'd5;
    localparam logic [3:0] CMD_RELATIVE_ADDR = 4'd6;
    localparam logic [3:0] CMD_SELECT = 4'd7;
    localparam logic [3:0] CMD_READ_SINGLE = 4'd8;
    localparam logic [3:0] CMD_SET_BUS_WIDTH = 4'd9;

`ifdef SD_CARD_MODEL_4BIT
    localparam bit ALLOW_4BIT = 1'b1;
`else
    localparam bit ALLOW_4BIT = 1'b0;
`endif

    logic sd_cmd_out;
    logic sd_cmd_oe;
    logic [3:0] sd_dat_out;
    logic [3:0] sd_dat_oe;
    logic command_valid;
    logic [5:0] command_index;
    logic [31:0] command_argument;
    logic [3:0] command_kind;
    logic [2:0] card_state;
    logic app_cmd_pending;
    logic [7:0] acmd41_count;
    logic bus_width_4bit;
    logic command_illegal;
    logic acmd41_ready;
    logic response_start;
    logic [135:0] response_frame;
    logic [7:0] response_length;
    logic response_busy;
    logic response_done;
    logic data_start;
    logic data_busy;
    logic data_done;
    logic read_pending;
    logic [31:0] read_block_address;
    logic [31:0] memory_offset;
    logic [7:0] memory_data;
    logic [31:0] r1_status;
    logic [119:0] fixed_cid;
    logic selected_response_illegal;

    assign sd_cmd = sd_cmd_oe ? sd_cmd_out : 1'bz;
`ifdef SD_CARD_MODEL_4BIT
    assign sd_dat = sd_dat_oe ? sd_dat_out : 4'bzzzz;
`else
    assign sd_dat0 = sd_dat_oe[0] ? sd_dat_out[0] : 1'bz;
`endif

    sd_command_receiver command_receiver (
        .sd_clk(sd_clk), .sd_reset_n(sd_reset_n), .card_cmd_oe(sd_cmd_oe), .sd_cmd_in(sd_cmd),
        .command_valid(command_valid), .command_index(command_index),
        .command_argument(command_argument)
    );

    sd_command_decoder command_decoder (
        .command_index(command_index), .app_cmd_pending(app_cmd_pending),
        .command_kind(command_kind)
    );

    sd_state_manager #(.ALLOW_4BIT(ALLOW_4BIT)) state_manager (
        .sd_clk(sd_clk), .sd_reset_n(sd_reset_n), .command_valid(command_valid),
        .command_index(command_index), .command_kind(command_kind), .command_argument(command_argument),
        .card_state(card_state), .app_cmd_pending(app_cmd_pending),
        .acmd41_count(acmd41_count), .bus_width_4bit(bus_width_4bit),
        .command_illegal(command_illegal),
        .acmd41_ready(acmd41_ready)
    );

    sd_response_generator response_generator (
        .sd_clk(sd_clk), .sd_reset_n(sd_reset_n), .response_start(response_start),
        .response_frame(response_frame), .response_length(response_length),
        .sd_cmd_out(sd_cmd_out), .sd_cmd_oe(sd_cmd_oe),
        .response_busy(response_busy), .response_done(response_done)
    );

    sd_memory_reader #(
        .IMAGE_FILE(IMAGE_FILE), .IMAGE_SIZE_BYTES(IMAGE_SIZE_BYTES),
        .BLOCK_SIZE_BYTES(BLOCK_SIZE_BYTES)
    ) memory_reader (
        .block_address(read_block_address), .byte_offset(memory_offset),
        .data_out(memory_data)
    );

    sd_data_sender #(
        .RESPONSE_DELAY(RESPONSE_DELAY), .BLOCK_SIZE_BYTES(BLOCK_SIZE_BYTES)
    ) data_sender (
        .sd_clk(sd_clk), .sd_reset_n(sd_reset_n), .start(data_start),
        .block_address(read_block_address), .memory_data(memory_data),
        .memory_offset(memory_offset), .bus_width_4bit(bus_width_4bit),
        .sd_dat_out(sd_dat_out), .sd_dat_oe(sd_dat_oe),
        .busy(data_busy), .done(data_done)
    );

    always_comb begin
        r1_status = 32'h00000000;
        r1_status[22] = command_valid ? command_illegal : selected_response_illegal;
        r1_status[0] = card_state == CARD_IDLE;
        r1_status[5] = command_kind == CMD_APP;
        r1_status[12:9] = card_state;
        fixed_cid = {8'h01, 16'h0000, 40'h5254495344, 8'h00, 32'h12345678, 4'h0, 12'h000};
    end

    always_ff @(posedge sd_clk or negedge sd_reset_n) begin
        if (!sd_reset_n) begin
            response_start <= 1'b0;
            response_frame <= '0;
            response_length <= '0;
            data_start <= 1'b0;
            read_pending <= 1'b0;
            read_block_address <= '0;
            selected_response_illegal <= 1'b0;
        end else begin
            response_start <= 1'b0;
            data_start <= 1'b0;

            if (command_valid && command_kind == CMD_GO_IDLE) begin
                read_pending <= 1'b0;
            end else if (command_valid && !response_busy && !data_busy) begin
                selected_response_illegal <= command_illegal;
                if (command_kind != CMD_UNKNOWN || command_index == 6'd41) begin
                    if (command_index == 6'd0) begin
                        selected_response_illegal <= 1'b0;
                    end else if (command_kind == CMD_ALL_CID && !command_illegal) begin
                        response_frame <= {2'b00, 6'b111111, fixed_cid, 7'b0, 1'b1};
                        response_length <= 8'd136;
                        response_start <= 1'b1;
                    end else begin
                        case (command_kind)
                            CMD_SEND_IF_COND: begin
                                if (command_illegal)
                                    response_frame <= {{2'b00, command_index, r1_status, 7'b0, 1'b1}, 88'b0};
                                else
                                    response_frame <= {{2'b00, 6'd8, 32'h000001AA, 7'b0, 1'b1}, 88'b0};
                                response_length <= 8'd48;
                                response_start <= 1'b1;
                            end
                            CMD_APP, CMD_OP_COND, CMD_SELECT, CMD_READ_SINGLE,
                            CMD_RELATIVE_ADDR, CMD_ALL_CID, CMD_SET_BUS_WIDTH, CMD_UNKNOWN: begin
                                if (command_kind == CMD_RELATIVE_ADDR && !command_illegal) begin
                                    response_frame <= {{2'b00, 6'd3, 16'h1234, 16'h0000, 7'b0, 1'b1}, 88'b0};
                                end else if (command_kind == CMD_OP_COND) begin
                                    response_frame <= {{2'b00, 6'b111111,
                                        {acmd41_count >= 8'd2, 31'h40FF8000}, 7'b0, 1'b1}, 88'b0};
                                end else begin
                                    response_frame <= {{2'b00, command_index, r1_status, 7'b0, 1'b1}, 88'b0};
                                end
                                response_length <= 8'd48;
                                response_start <= 1'b1;
                                if (command_kind == CMD_READ_SINGLE && !command_illegal) begin
                                    read_block_address <= command_argument;
                                    read_pending <= 1'b1;
                                end
                            end
                            default: begin end
                        endcase
                    end
                end else begin
                    response_frame <= {{2'b00, command_index, 32'h00400000, 7'b0, 1'b1}, 88'b0};
                    response_length <= 8'd48;
                    response_start <= 1'b1;
                    selected_response_illegal <= 1'b1;
                end
            end

            if (response_done && read_pending) begin
                data_start <= 1'b1;
                read_pending <= 1'b0;
            end

            if (data_done)
                $display("[SD] CMD17 complete");
        end
    end
endmodule