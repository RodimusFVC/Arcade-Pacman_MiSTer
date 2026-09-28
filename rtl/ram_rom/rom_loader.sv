//============================================================================
//
//  Pac-Man ROM loader
//  ROM layout matched to MAME pacman.cpp regions
//
//============================================================================

// ioctl index 0 (MRA), all images stored exactly as dumped:
//   0x00000 - 0x0FFFF  main CPU          "maincpu"
//   0x10000 - 0x13FFF  tiles + sprites   "gfx1"
//   0x14000 - 0x1401F  palette PROM      "proms" 0x000
//   0x14020 - 0x1411F  colour lookup     "proms" 0x020
//   0x14400 - 0x144FF  waveform PROM     "namco" 0x000 (0x100 timing PROM is not loaded)
//
// ioctl index 1: board variant, flags and input map (see the top level)
// ioctl indexes 3 and 4 are reserved for hiscore config and NVRAM

module selector
(
    input  logic [24:0] ioctl_addr,
    output logic        prog_cs,
    output logic        gfx_cs,
    output logic        pal_cs,
    output logic        lut_cs,
    output logic        wave_cs
);
    always_comb begin
        {prog_cs, gfx_cs, pal_cs, lut_cs, wave_cs} = '0;

        if      (ioctl_addr < 25'h10000) prog_cs = 1'b1;
        else if (ioctl_addr < 25'h14000) gfx_cs  = 1'b1;
        else if (ioctl_addr < 25'h14020) pal_cs  = 1'b1;
        else if (ioctl_addr < 25'h14120) lut_cs  = 1'b1;
        else if (ioctl_addr >= 25'h14400 && ioctl_addr < 25'h14500) wave_cs = 1'b1;
    end
endmodule
