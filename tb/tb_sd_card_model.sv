`timescale 1ns/1ps

module tb_sd_card_model;
    logic sd_clk = 1'b0;
    logic sd_reset_n = 1'b0;
    logic host_cmd_oe = 1'b0;
    logic host_cmd_out = 1'b1;
    tri1 sd_cmd;
    tri1 sd_dat0;
    logic [47:0] command_frame;
    logic [135:0] response_frame;
    logic [7:0] received_byte;
    time response_end_time;

    assign sd_cmd = host_cmd_oe ? host_cmd_out : 1'bz;

    sd_card_model #(
        .IMAGE_FILE("tb/boot.mem"),
        .IMAGE_SIZE_BYTES(1024),
        .BLOCK_SIZE_BYTES(512),
        .RESPONSE_DELAY(8)
    ) dut (
        .sd_reset_n(sd_reset_n), .sd_clk(sd_clk),
        .sd_cmd(sd_cmd), .sd_dat0(sd_dat0)
    );

    always #5 sd_clk = ~sd_clk;

    task automatic fail(input string message);
        begin
            $display("[FAIL] %s", message);
            $fatal(1);
        end
    endtask

    task automatic pass(input string message);
        begin
            $display("[PASS] %s", message);
        end
    endtask

    task automatic send_command(input logic [5:0] command_index, input logic [31:0] argument);
        begin
            command_frame = {1'b0, 1'b1, command_index, argument, 7'h00, 1'b1};
            for (integer bit_index = 47; bit_index >= 0; bit_index = bit_index - 1) begin
                @(negedge sd_clk);
                host_cmd_oe = 1'b1;
                host_cmd_out = command_frame[bit_index];
            end
            @(negedge sd_clk);
            host_cmd_oe = 1'b0;
            host_cmd_out = 1'b1;
        end
    endtask

    task automatic receive_response(input integer response_bits, output logic [135:0] result);
        integer cycles;
        begin
            result = '0;
            cycles = 0;
            while (sd_cmd !== 1'b0 && cycles < 64) begin
                @(posedge sd_clk);
                #1;
                cycles = cycles + 1;
            end
            if (cycles == 64) fail("Timed out waiting for CMD response start");
            result[response_bits-1] = sd_cmd;
            for (integer bit_index = response_bits - 2; bit_index >= 0; bit_index = bit_index - 1) begin
                @(posedge sd_clk);
                #1;
                result[bit_index] = sd_cmd;
                if (bit_index == 0) response_end_time = $time;
            end
            @(posedge sd_clk);
            #1;
        end
    endtask

    task automatic check_r1(input logic expected_illegal, input string label);
        begin
            receive_response(48, response_frame);
            if (response_frame[47:46] !== 2'b00) fail({label, ": response framing"});
            if (response_frame[30] !== expected_illegal) fail({label, ": ILLEGAL_COMMAND bit mismatch"});
        end
    endtask

    task automatic read_and_check_block(input logic [31:0] block_number, input logic expect_pattern);
        logic [7:0] expected_byte;
        integer cycles;
        begin
            send_command(6'd17, block_number);
            check_r1(1'b0, "CMD17 R1");
            cycles = 0;
            while (sd_dat0 !== 1'b0 && cycles < 64) begin
                @(posedge sd_clk);
                #1;
                cycles = cycles + 1;
            end
            if (cycles == 64) fail("Timed out waiting for DAT0 start bit");
            if (($time - response_end_time) / 10 != 8) fail("CMD17 DAT0 response delay was not 8 clocks");
            for (integer byte_index = 0; byte_index < 512; byte_index = byte_index + 1) begin
                received_byte = '0;
                for (integer bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                    @(posedge sd_clk);
                    #1;
                    received_byte[bit_index] = sd_dat0;
                end
                expected_byte = 8'h00;
                if (expect_pattern && byte_index == 0) expected_byte = 8'hA5;
                if (expect_pattern && byte_index == 1) expected_byte = 8'h3C;
                if (received_byte !== expected_byte) begin
                    $display("[FAIL] CMD17 block=%0d byte=%0d expected=%02h actual=%02h",
                        block_number, byte_index, expected_byte, received_byte);
                    $fatal(1);
                end
            end
            for (integer crc_bit = 0; crc_bit < 16; crc_bit = crc_bit + 1) begin
                @(posedge sd_clk);
                #1;
                if (sd_dat0 !== 1'b0) fail("Dummy CRC16 was not zero");
            end
            @(posedge sd_clk);
            #1;
            if (sd_dat0 !== 1'b1) fail("DAT0 end bit was not one");
            @(posedge sd_clk);
            #1;
            if (sd_dat0 !== 1'b1) fail("DAT0 was not released to High-Z");
        end
    endtask

    initial begin
        #2000000;
        fail("Global simulation timeout");
    end

    initial begin
        repeat (3) @(negedge sd_clk);
        sd_reset_n = 1'b1;
        repeat (2) @(negedge sd_clk);
        if (sd_cmd !== 1'b1 || sd_dat0 !== 1'b1) fail("Reset did not release CMD/DAT0");
        pass("TC001 reset");

        send_command(6'd0, 32'h00000000);
        send_command(6'd8, 32'h000001AA);
        receive_response(48, response_frame);
        if (response_frame[39:8] !== 32'h000001AA) fail("CMD8 R7 echo mismatch");
        for (integer attempt = 0; attempt < 3; attempt = attempt + 1) begin
            send_command(6'd55, 32'h00000000);
            check_r1(1'b0, "CMD55");
            send_command(6'd41, 32'h40FF8000);
            receive_response(48, response_frame);
            if (response_frame[39:8] !== (attempt == 2 ? 32'hC0FF8000 : 32'h40FF8000))
                fail("ACMD41 OCR or ready bit timing mismatch");
        end

        send_command(6'd2, 32'h00000000);
        receive_response(136, response_frame);
        if (response_frame[127:120] !== 8'h01) fail("CMD2 CID manufacturer ID mismatch");
        if (response_frame[103:64] !== 40'h5254495344) fail("CMD2 CID product name mismatch");
        if (response_frame[55:24] !== 32'h12345678) fail("CMD2 CID serial mismatch");

        send_command(6'd3, 32'h00000000);
        receive_response(48, response_frame);
        if (response_frame[39:24] !== 16'h1234) fail("CMD3 RCA mismatch");

        send_command(6'd7, 32'h99990000);
        check_r1(1'b1, "CMD7 RCA mismatch");
        pass("TC009 RCA mismatch");
        send_command(6'd7, 32'h12340000);
        check_r1(1'b0, "CMD7 select");
        pass("TC002 initialization and card selection");

        read_and_check_block(32'd0, 1'b1);
        pass("TC003 block zero data");
        pass("TC005 MSB-first byte order");
        read_and_check_block(32'd1, 1'b0);
        pass("TC004 arbitrary block address");
        read_and_check_block(32'd0, 1'b1);
        pass("TC010 consecutive CMD17 reads");
        read_and_check_block(32'd2, 1'b0);
        pass("TC006 out-of-range zero fill");

        send_command(6'd0, 32'h00000000);
        send_command(6'd17, 32'h00000000);
        check_r1(1'b1, "CMD17 in IDLE");
        if (sd_dat0 !== 1'b1) fail("Invalid CMD17 started a data transfer");
        pass("TC007 invalid state");

        send_command(6'd24, 32'h00000000);
        check_r1(1'b1, "CMD24 unsupported");
        pass("TC008 unsupported command");

        $display("[PASS] All test cases passed");
        $finish;
    end
endmodule