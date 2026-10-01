module sd_memory_reader #(
    parameter IMAGE_FILE = "boot.mem",
    parameter integer IMAGE_SIZE_BYTES = 32 * 1024 * 1024,
    parameter integer BLOCK_SIZE_BYTES = 512
) (
    input  logic [31:0] block_address,
    input  logic [31:0] byte_offset,
    output logic [7:0]  data_out
);
    logic [7:0] image_mem [0:IMAGE_SIZE_BYTES-1];
    logic [63:0] block_base;
    logic [63:0] absolute_address;

    assign block_base = block_address * BLOCK_SIZE_BYTES;
    assign absolute_address = block_base + byte_offset;

    initial begin
        $readmemh(IMAGE_FILE, image_mem);
    end

    always_comb begin
        data_out = 8'h00;
        if (block_base + BLOCK_SIZE_BYTES <= IMAGE_SIZE_BYTES && absolute_address < IMAGE_SIZE_BYTES) begin
            data_out = image_mem[absolute_address];
            if ((^data_out) === 1'bx) data_out = 8'h00;
        end
    end
endmodule