module sd_command_decoder (
    input  logic [5:0] command_index,
    input  logic       app_cmd_pending,
    output logic [3:0] command_kind
);
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
        command_kind = CMD_UNKNOWN;
        case (command_index)
            6'd0: command_kind = CMD_GO_IDLE;
            6'd8: command_kind = CMD_SEND_IF_COND;
            6'd55: command_kind = CMD_APP;
            6'd41: if (app_cmd_pending) command_kind = CMD_OP_COND;
            6'd2: command_kind = CMD_ALL_CID;
            6'd3: command_kind = CMD_RELATIVE_ADDR;
            6'd7: command_kind = CMD_SELECT;
            6'd17: command_kind = CMD_READ_SINGLE;
            default: command_kind = CMD_UNKNOWN;
        endcase
    end
endmodule