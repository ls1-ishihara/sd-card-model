# Simplified SD Card Model

SystemVerilog functional model for an SD Native 1-bit host. The model supports the initialization commands and single-block CMD17 reads described in [the specification](spec/spec_sd_card_model.md).

## Contents

- `rtl/`: command receiver/decoder, state manager, response generator, memory reader, data sender, and top-level model.
- `tb/tb_sd_card_model.sv`: self-checking initialization and data-transfer tests.
- `tb/boot.mem`: sample image. Uninitialized image locations and out-of-range blocks read as zero.

## Run tests

Install Icarus Verilog, then run these commands from this directory:

```powershell
iverilog -g2012 -s tb_sd_card_model -o tb_sd_card_model.vvp rtl/*.sv tb/tb_sd_card_model.sv
vvp tb_sd_card_model.vvp
```

The testbench prints a PASS line for each test group and exits with a nonzero status on the first failure. The generated `.vvp` file can be deleted after the run.

## Integration

Instantiate `sd_card_model` and connect `sd_reset_n`, `sd_clk`, `sd_cmd`, and `sd_dat0` to the host's SD Native interface. Set `IMAGE_FILE` to a `$readmemh` file containing one hexadecimal byte per line. The default block size is 512 bytes and the default image capacity is 32 MiB.