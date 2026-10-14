# Simplified SD Card Model

SystemVerilog functional model for an SD Native host. The default build exposes a 1-bit DAT interface; defining `SD_CARD_MODEL_4BIT` exposes a 4-bit DAT interface and enables ACMD6 bus-width switching. Both builds start in 1-bit mode. See [the specification](spec/spec_sd_card_model.md) for details.

## Contents

- `rtl/`: command receiver/decoder, state manager, response generator, memory reader, data sender, and top-level model.
- `tb/tb_sd_card_model.sv`: self-checking initialization and data-transfer tests.
- `tb/boot.mem`: sample image. Uninitialized image locations and out-of-range blocks read as zero.
- `verif/`: waveform screenshots and walkthroughs for reviewed test runs.
- [Waveform walkthrough](verif/waveform_walkthrough.md): waveform dump commands and a concise behavior summary.
- [Waveform walkthrough2](verif/waveform_walkthrough2.md): viewer screenshots, measured timing, and an RTL signal-tracing guide (Japanese).
- [1-bit / 4-bit waveform walkthrough](verif/waveform_walkthrough_4bit.md): define builds, ACMD6 switching, measured transfer windows, and comparison waveforms.

## Run tests

Install Icarus Verilog, then run these commands from this directory:

```powershell
iverilog -g2012 -s tb_sd_card_model -o tb_sd_card_model.vvp rtl/*.sv tb/tb_sd_card_model.sv
vvp tb_sd_card_model.vvp
```

The testbench prints a PASS line for each test group and exits with a nonzero status on the first failure. The generated `.vvp` file can be deleted after the run.

To test the optional 4-bit interface and runtime ACMD6 switching:

```powershell
iverilog -g2012 -D SD_CARD_MODEL_4BIT -s tb_sd_card_model -o tb_sd_card_model_4bit.vvp rtl/*.sv tb/tb_sd_card_model.sv
vvp tb_sd_card_model_4bit.vvp
```

The 4-bit test switches 1-bit -> 4-bit -> 1-bit -> 4-bit and checks all 512 bytes in each mode.

To generate a VCD waveform, define `SD_CARD_MODEL_DUMP_WAVEFORM` when compiling:

```powershell
iverilog -g2012 -D SD_CARD_MODEL_DUMP_WAVEFORM -s tb_sd_card_model -o tb_sd_card_model.vvp rtl/*.sv tb/tb_sd_card_model.sv
vvp tb_sd_card_model.vvp
```

This writes `sd_card_model.vcd` in the current directory. Without the define, no VCD is produced. Open the VCD with `waveform_viewer` or another VCD viewer.

For a 4-bit-interface waveform, combine both defines:

```powershell
iverilog -g2012 -D SD_CARD_MODEL_4BIT -D SD_CARD_MODEL_DUMP_WAVEFORM -s tb_sd_card_model -o tb_sd_card_model_4bit.vvp rtl/*.sv tb/tb_sd_card_model.sv
vvp tb_sd_card_model_4bit.vvp
```

Waveform names are `sd_card_model_1bit.vcd` and `sd_card_model_4bit.vcd`, respectively.

## Integration

Instantiate `sd_card_model` and connect `sd_reset_n`, `sd_clk`, and `sd_cmd` to the host's SD Native interface. The default build exposes `sd_dat0`; a build with `SD_CARD_MODEL_4BIT` exposes `sd_dat[3:0]`. Set `IMAGE_FILE` to a `$readmemh` file containing one hexadecimal byte per line. The default block size is 512 bytes and the default image capacity is 32 MiB.
