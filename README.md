<h1 align="center">Pac-Man Hardware FPGA Core</h1>

<p align="center">
  Arcade hardware implementation for MiSTer FPGA
</p>

---

## Overview

FPGA implementation of the **Namco / Midway Pac-Man hardware (1980)** and the many boards built on or around it, in a single core.

Every set in MAME's `pacman.cpp`, `jrpacman.cpp`, `pengo.cpp` and `schick.cpp` drivers is supported — 163 MAME sets plus Pac-Manic Miner — including the Ms. Pac-Man auxiliary board, Jr. Pac-Man, Sega Pengo, the Epos daughterboards, the S2650 conversion boards and the SDRAM-based trivia games.

This core targets MiSTer FPGA and aims for accurate gameplay behavior, video timing, and sound reproduction.

---

## Supported Games

| Hardware | Games |
|----------|-------|
| Pac-Man (Namco / Midway) | Puck Man, Pac-Man, Pac-Man Plus, Eyes, Mr. TNT, Lizard Wizard, Jump Shot, Shoot the Bull, Eggor, Crush Roller, Birdiy, Ali Baba and 40 Thieves, Cannon Ball, Number Crash, Club Pac-Man |
| Ms. Pac-Man auxiliary board | Ms. Pac-Man and bootlegs, Ms. Pac-Man Twin |
| Bootleg / conversion boards | Woodpecker, Ponpoko, Naughty Mouse, Dream Shopper, Van-Van Car, Pac-Manic Miner |
| Epos daughterboard | The Glob, Boardwalk Casino, Eeekk! |
| Jr. Pac-Man | Jr. Pac-Man |
| Sega Pengo | Pengo (all encryption variants), Penta |
| S2650 conversions | Driving Force, Eight Ball Action, Porky |
| SDRAM trivia / quiz boards | MTV Rock-N-Roll Trivia, Big Bucks, Super ABC |
| Microhard | Super Chick |

Clones and regional versions are in `releases/_alternatives/`.

---

## Controls

Default MiSTer gamepad mapping (button names are set per game by its `.mra`):

| Input | Action |
|-------|--------|
| D-Pad / Joystick | Move |
| A | Button 1 |
| Y | Button 2 |
| B | Button 3 |
| X | Button 4 |
| Select | Insert Coin |
| Start | 1 Player Start |
| Right Shoulder | 2 Player Start |
| Left Shoulder | Pause |

Button 5, Button 6 and **Rack Test** (the level-skip cheat, on games that have it) are available but unassigned — map them in the OSD's *Define Buttons* if wanted.

Shoot the Bull's trackball works from a mouse, the left analog stick, or the D-pad (speed under *Game Options*).

---

## Features

- One core for every supported board, selected by the `.mra`
- Arcade-accurate CPU and sync-bus timing
- Namco WSG, AY-3-8910 and SN76496 sound as fitted to each board
- Encrypted and protected sets decoded in hardware, as the original boards did
- High score saving support (130 sets)
- DIP switches for every set, taken from MAME
- CRT and HDMI flip, pause, and scandoubler options
- MiSTer-compatible .mra provided
- Verified ROM definitions with checksums

---

## ROM Requirements

ROM files are **not included**.

To use this arcade core, you must provide legally obtained ROM files.

To simplify setup:

- `.mra` files are provided in the **Releases** section.
- The `.mra` specifies all required ROM files along with checksums.
- The ROM `.zip` filename corresponds to the naming convention used by the MAME project.

For setup instructions and environment configuration, refer to:

MiSTer Arcade ROM guide:  
https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms

---

## Installation

1. Copy the core `.rbf` file to your MiSTer `/_Arcade/cores` folder.
2. Copy the `.mra` files (including the `_alternatives` folder) to your MiSTer `/_Arcade` folder.
3. Place the appropriate ROM `.zip` files in your `/games/mame` directory.
4. Launch the core from the MiSTer Arcade menu.

---

## Legal Notice

This project contains **no copyrighted game data**.

Users are responsible for obtaining and using ROM files in accordance with applicable laws.

Do not request ROM files in issues or discussions.

---

## Credits

FPGA core development: RodimusFVC  
Board model derived from "A simulation model of Pacman hardware" by MikeJ (fpgaarcade.com) and the MiSTer Pac-Man port by Alexey Melnikov (Sorgelig)  
Memory maps, decryption and protection per the MAME project (Nicola Salmoria, David Haywood and contributors)  
T80 CPU core: Daniel Wallner, with updates by Sorgelig  
S2650 CPU core: from the MiSTer Arcadia core  
JT49 / JT89 sound cores: Jose Tejada (jotego)  
SDRAM controller: Sorgelig  
Hiscore, pause and NVRAM modules: Jim Gregory and Alan Steremberg  
Audio filters: Gregory Hogan (Soltan_G42)  
Original arcade games © Namco, Midway, Sega and their respective owners

---
