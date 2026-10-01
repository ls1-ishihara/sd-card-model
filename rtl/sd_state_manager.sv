module sd_state_manager (
    input  logic       sd_clk,
    input  logic       sd_reset_n,
    input  logic       command_valid,
    input  logic [5:0] command_index,
    input  logic [3:0] command_kind,
    input  logic [31:0] command_argument,
    output logic [2:0] card_state,
    output logic       app_cmd_pending,
    output logic [7:0] acmd41_count,
    output logic       command_illegal,
    output logic       acmd41_ready
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

    always_comb begin
        command_illegal = 1'b0;
        if (command_valid && command_kind != CMD_GO_IDLE) begin
            case (command_kind)
                CMD_SEND_IF_COND: command_illegal = card_state != CARD_IDLE;
                CMD_APP: command_illegal = card_state != CARD_IDLE;
                CMD_OP_COND: command_illegal = card_state != CARD_IDLE;
                CMD_ALL_CID: command_illegal = card_state != CARD_READY;
                CMD_RELATIVE_ADDR: command_illegal = card_state != CARD_IDENT;
                CMD_SELECT: command_illegal = card_state != CARD_STANDBY && card_state != CARD_TRANSFER;
                CMD_READ_SINGLE: command_illegal = card_state != CARD_TRANSFER;
                default: command_illegal = 1'b1;
            endcase
            if (command_kind == CMD_SELECT && command_argument[31:16] != 16'h1234)
                command_illegal = 1'b1;
        end
    end

    assign acmd41_ready = acmd41_count >= 8'd3;

    always_ff @(posedge sd_clk or negedge sd_reset_n) begin
        if (!sd_reset_n) begin
            card_state <= CARD_IDLE;
            app_cmd_pending <= 1'b0;
            acmd41_count <= '0;
        end else if (command_valid) begin
            if (command_kind == CMD_GO_IDLE) begin
                card_state <= CARD_IDLE;
                app_cmd_pending <= 1'b0;
                acmd41_count <= '0;
            end else begin
                app_cmd_pending <= 1'b0;
                if (!command_illegal) begin
                    case (command_kind)
                        CMD_APP: app_cmd_pending <= 1'b1;
                        CMD_OP_COND: begin
                            if (acmd41_count != 8'hff)
                                acmd41_count <= acmd41_count + 1'b1;
                            if (acmd41_count >= 8'd2)
                                card_state <= CARD_READY;
                        end
                        CMD_ALL_CID: card_state <= CARD_IDENT;
                        CMD_RELATIVE_ADDR: card_state <= CARD_STANDBY;
                        CMD_SELECT: card_state <= CARD_TRANSFER;
                        default: begin end
                    endcase
                end
            end
        end
    end

    always_ff @(posedge sd_clk) begin
        if (sd_reset_n && command_valid) begin
            if (command_kind == CMD_GO_IDLE) begin
                $display("[SD] CMD0 received");
                if (card_state != CARD_IDLE) $display("[SD] State %0d -> IDLE", card_state);
            end else if (command_illegal) begin
                $display("[SD][ERROR] CMD%0d received in CARD_STATE_%0d", command_index, card_state);
            end else begin
                case (command_kind)
                    CMD_SEND_IF_COND: $display("[SD] CMD8 arg=0x%08h", command_argument);
                    CMD_APP: $display("[SD] CMD55 received");
                    CMD_OP_COND: begin
                        $display("[SD] ACMD41 count=%0d ready=%0d", acmd41_count + 1'b1, acmd41_count >= 2);
                        if (acmd41_count >= 2) $display("[SD] State IDLE -> READY");
                    end
                    CMD_ALL_CID: begin
                        $display("[SD] CMD2 send CID");
                        $display("[SD] State READY -> IDENT");
                    end
                    CMD_RELATIVE_ADDR: begin
                        $display("[SD] CMD3 RCA=0x1234");
                        $display("[SD] State IDENT -> STANDBY");
                    end
                    CMD_SELECT: begin
                        $display("[SD] CMD7 select RCA=0x1234");
                        if (card_state == CARD_STANDBY) $display("[SD] State STANDBY -> TRANSFER");
                    end
                    CMD_READ_SINGLE: $display("[SD] CMD17 block=%0d", command_argument);
                    default: $display("[SD][ERROR] Unsupported command CMD%0d", command_index);
                endcase
            end
        end
    end
endmodule