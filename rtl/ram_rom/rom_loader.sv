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
//   0x14020 - 0x1411F  colour lookup     "proms" 0x020 (Pengo's 1K lookup occupies up to 0x1441F)
//   0x14600 - 0x146FF  Jr palette 9E     "proms" low nibbles (ROM_LOAD_NIB_LOW)
//   0x14700 - 0x147FF  Jr palette 9F     "proms" high nibbles (ROM_LOAD_NIB_HIGH)
//   0x14800 - 0x148FF  waveform PROM     "namco" 0x000 (0x100 timing PROM is not loaded)
//   0x15000 - 0x15FFF  Ali Baba clock    "gfx2" (the same 2K ROM loaded twice)
//   0x18000 - 0x1FFFF  S2650 boards      "gfx1" (32K: tiles 0x0000, sprites 0x4000)
//   0x20000 - 0x3FFFF  Super ABC gfx     "user1" (descrambled into the 64K gfx store as it loads)
//   0x40000 - 0x4FFFF  Super Chick       "gfx1" (64K, 4bpp: planes 2/3 in the upper half)
//   0x50000 - 0x57FFF  Super Chick       "audiocpu"
//
// ioctl index 2: SDRAM (Rock Tris / Big Bucks "user1" questions, Super ABC "maincpu")
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
    output logic        wave_cs,
    output logic        jr_lo_cs,
    output logic        jr_hi_cs,
    output logic        gfx2_cs,
    output logic        sabc_gfx_cs,
    output logic        s26_gfx_cs,
    output logic        sch_gfx_cs,
    output logic        sch_snd_cs
);
    always_comb begin
        {prog_cs, gfx_cs, pal_cs, lut_cs, wave_cs, jr_lo_cs, jr_hi_cs, gfx2_cs, sabc_gfx_cs, s26_gfx_cs, sch_gfx_cs, sch_snd_cs} = '0;

        if      (ioctl_addr < 25'h10000) prog_cs = 1'b1;
        else if (ioctl_addr < 25'h14000) gfx_cs  = 1'b1;
        else if (ioctl_addr < 25'h14020) pal_cs  = 1'b1;
        else if (ioctl_addr < 25'h14120) lut_cs  = 1'b1;
        else if (ioctl_addr >= 25'h14600 && ioctl_addr < 25'h14620) jr_lo_cs = 1'b1;
        else if (ioctl_addr >= 25'h14700 && ioctl_addr < 25'h14720) jr_hi_cs = 1'b1;
        else if (ioctl_addr >= 25'h14800 && ioctl_addr < 25'h14900) wave_cs = 1'b1;
        else if (ioctl_addr >= 25'h15000 && ioctl_addr < 25'h16000) gfx2_cs = 1'b1;
        else if (ioctl_addr >= 25'h18000 && ioctl_addr < 25'h20000) s26_gfx_cs = 1'b1;
        else if (ioctl_addr >= 25'h20000 && ioctl_addr < 25'h40000) sabc_gfx_cs = 1'b1;
        else if (ioctl_addr >= 25'h40000 && ioctl_addr < 25'h50000) sch_gfx_cs = 1'b1;
        else if (ioctl_addr >= 25'h50000 && ioctl_addr < 25'h58000) sch_snd_cs = 1'b1;
    end
endmodule
