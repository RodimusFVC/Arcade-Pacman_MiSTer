#!/usr/bin/env python3
"""Generate MRAs for the Pac-Man core straight from MAME pacman.cpp.

Region placement matches rtl/ram_rom/rom_loader.sv; images are copied as dumped.
DIP switches and the input map come from the set's MAME INPUT_PORTS.

Release layout: a parent set (MAME parent 0) goes to <releases>/<Title>.mra with the
trailing parentheses dropped; a clone goes to
<releases>/_alternatives/_<Parent Title>/<Full Title>.mra.

Usage:
    gen_mra.py <pacman.cpp> <releases_dir> [set ...]      (no sets: every supported set)
"""
import copy
import re
import sys
from pathlib import Path

MAME_VERSION = "0289"
RBF = "Pacman"

# region -> (base in ioctl index 0, size taken)
REGIONS = {
    "maincpu": (0x00000, 0x10000),
    "gfx1":    (0x10000, 0x04000),
    "proms":   (0x14000, 0x00400),
    "namco":   (0x14400, 0x00100),                  # waveform PROM; the timing PROM at 0x100 is not used
}

# (machine config, init) pairs the board implements, -> board variant byte
SUPPORTED = {
    ("pacman", "empty_init"): 0,
}

F_4WAY, F_VERT, F_ROT90 = 0x01, 0x10, 0x80

# port order on the board: DIP bytes 0-3 and input map bytes 16-47
PORTS = ["IN0", "IN1", "DSW1", "DSW2"]

# control ids (Arcade-Pacman.sv)
CTL = {("JOYSTICK_UP", 1): 1, ("JOYSTICK_DOWN", 1): 2, ("JOYSTICK_LEFT", 1): 3, ("JOYSTICK_RIGHT", 1): 4,
       ("BUTTON1", 1): 5, ("BUTTON2", 1): 6, ("BUTTON3", 1): 7, ("BUTTON4", 1): 8,
       ("JOYSTICK_UP", 2): 9, ("JOYSTICK_DOWN", 2): 10, ("JOYSTICK_LEFT", 2): 11, ("JOYSTICK_RIGHT", 2): 12,
       ("BUTTON1", 2): 13, ("BUTTON2", 2): 14, ("BUTTON3", 2): 15, ("BUTTON4", 2): 16,
       ("COIN1", 0): 17, ("COIN2", 0): 18, ("START1", 0): 19, ("START2", 0): 20,
       ("TILT", 0): 21, ("SERVICE1", 0): 22, ("SERVICE", 0): 22}
IGNORED_TYPES = {"UNUSED", "UNKNOWN"}

SERIES_BY_PARENT = {"puckman": ("Pac-Man", "Maze"), "eyes": ("Eyes", "Maze"), "mrtnt": ("Mr. TNT", "Maze"),
                    "theglobp": ("The Glob", "Maze"), "pacplus": ("Pac-Man", "Maze")}
REGION_WORDS = [("US", "US"), ("Japan", "Japan"), ("Spanish", "Spain"), ("Italian", "Italy"), ("French", "France"),
                ("Brazil", "Brazil"), ("Argentina", "Argentina"), ("Greek", "Greece"), ("Hungarian", "Hungary")]

# ---------------------------------------------------------------- parsing

GAME_RE = re.compile(r'^GAME\(\s*([\w?]+),\s*(\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*(ROT\d+),\s*"([^"]*)",\s*"([^"]*)"', re.M)
LOAD_RE = re.compile(r'ROM_LOAD\(\s*"([^"]+)",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(?:BAD_DUMP\s+)?CRC\(([0-9a-fA-F]+)\)')
CONT_RE = re.compile(r'ROM_CONTINUE\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
REGION_RE = re.compile(r'ROM_REGION\(\s*(0x[0-9a-fA-F]+),\s*"([^"]+)"')
MACRO_RE = re.compile(r'\b(PORT_\w+|INPUT_PORTS_\w+)\b(\s*\(((?:[^()"]|"[^"]*"|\([^()]*\))*)\))?')


def parse_games(src):
    games = {}
    for m in GAME_RE.finditer(src):
        year, name, parent, machine, inputs, init, rot, manuf, desc = m.groups()
        games[name] = dict(year=year, name=name, parent=None if parent == "0" else parent,
                           machine=machine, inputs=inputs, init=init, rot=rot, manuf=manuf, desc=desc)
    return games


def parse_roms(src, setname):
    m = re.search(r'ROM_START\(\s*%s\s*\)(.*?)ROM_END' % re.escape(setname), src, re.S)
    if not m:
        raise SystemExit(f"ROM_START({setname}) not found")
    segs, region, rsize, last = [], None, 0, None
    for line in m.group(1).splitlines():
        line = line.split("//")[0]
        if (r := REGION_RE.search(line)):
            region, rsize, last = r.group(2), int(r.group(1), 16), None
        elif (l := LOAD_RE.search(line)):
            name, off, length, crc = l.group(1), int(l.group(2), 16), int(l.group(3), 16), l.group(4).lower()
            last = dict(name=name, crc=crc, src=0, dst=off, len=length, region=region, rsize=rsize)
            segs.append(last)
        elif (c := CONT_RE.search(line)):
            off, length = int(c.group(1), 16), int(c.group(2), 16)
            nxt = dict(last, src=last["src"] + last["len"], dst=off, len=length)
            segs.append(nxt)
            last = nxt
        elif "ROM_" in line and any(k in line for k in ("ROM_LOAD", "ROM_COPY", "ROM_FILL", "ROM_RELOAD")):
            raise SystemExit(f"{setname}: unhandled ROM statement: {line.strip()}")
    return segs


def def_str(s):
    s = s.strip()
    m = re.fullmatch(r'DEF_STR\(\s*(\w+)\s*\)', s)
    if not m:
        return s.strip('"')
    w = m.group(1)
    c = re.fullmatch(r'(\d+)C_(\d+)C', w)
    if c:
        return f"{c.group(1)}C/{c.group(2)}C"
    return w.replace("_", " ")


def split_args(a):
    out, depth, cur, q = [], 0, "", False
    for ch in a:
        if ch == '"':
            q = not q
        if not q and ch == "(":
            depth += 1
        elif not q and ch == ")":
            depth -= 1
        if ch == "," and depth == 0 and not q:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def parse_inputs(src):
    """INPUT_PORTS name -> {tag: [field]}; field = dict(mask, kind, default, type, player, name, settings, fourway)."""
    blocks = {m.group(1): m.group(2) for m in re.finditer(
        r'INPUT_PORTS_START\(\s*(\w+)\s*\)(.*?)INPUT_PORTS_END', src, re.S)}
    cache = {}

    def build(name):
        if name in cache:
            return copy.deepcopy(cache[name])
        ports, cur, fld = {}, None, None
        body = "\n".join(l.split("//")[0] for l in blocks[name].splitlines())
        for m in MACRO_RE.finditer(body):
            mac, args = m.group(1), split_args(m.group(3) or "")
            if mac == "PORT_INCLUDE":
                ports.update(build(args[0]))
            elif mac in ("PORT_START", "PORT_MODIFY"):
                cur = args[0].strip('"')
                if mac == "PORT_START":
                    ports[cur] = []
                fld = None
            elif mac in ("PORT_BIT", "PORT_DIPNAME", "PORT_CONFNAME", "PORT_SERVICE", "PORT_SERVICE_NO_TOGGLE",
                         "PORT_DIPUNUSED", "PORT_DIPUNUSED_DIPLOC", "PORT_DIPUNKNOWN", "PORT_DIPUNKNOWN_DIPLOC"):
                mask = int(args[0], 0)
                ports[cur] = [f for f in ports[cur] if not (f["mask"] & mask)]
                if mac == "PORT_BIT":
                    low = args[1] == "IP_ACTIVE_LOW"
                    t = args[2].replace("IPT_", "")
                    fld = dict(mask=mask, kind="unused" if t in IGNORED_TYPES else "input",
                               default=mask if low else 0, type=t, player=1, name=None, settings=[], fourway=False)
                elif mac in ("PORT_DIPNAME", "PORT_CONFNAME"):
                    fld = dict(mask=mask, kind="dip", default=int(args[1], 0), name=def_str(args[2]), settings=[])
                elif mac == "PORT_SERVICE":
                    low = args[1] == "IP_ACTIVE_LOW"
                    off, on = (mask, 0) if low else (0, mask)
                    fld = dict(mask=mask, kind="dip", default=off, name="Service Mode", settings=[(off, "Off"), (on, "On")])
                elif mac == "PORT_SERVICE_NO_TOGGLE":
                    low = args[1] == "IP_ACTIVE_LOW"
                    fld = dict(mask=mask, kind="input", default=mask if low else 0, type="SERVICE", player=0,
                               name=None, settings=[], fourway=False)
                else:
                    fld = dict(mask=mask, kind="unused", default=int(args[1], 0))
                ports[cur].append(fld)
            elif mac in ("PORT_DIPSETTING", "PORT_CONFSETTING"):
                fld["settings"].append((int(args[0], 0), def_str(args[1])))
            elif mac == "PORT_PLAYER":
                fld["player"] = int(args[0])
            elif mac == "PORT_COCKTAIL":
                fld["player"] = 2
            elif mac == "PORT_4WAY":
                fld["fourway"] = True
            elif mac == "PORT_NAME":
                fld["name"] = args[0].strip('"')
            elif mac in ("PORT_DIPLOCATION", "PORT_CODE", "PORT_TOGGLE", "PORT_8WAY", "PORT_IMPULSE", "PORT_CONDITION"):
                pass
            else:
                raise SystemExit(f"INPUT_PORTS({name}): unhandled {mac}")
        cache[name] = ports
        return copy.deepcopy(ports)

    return build


def place(segs, setname):
    out = []
    for s in segs:
        if s["region"] not in REGIONS:
            raise SystemExit(f"{setname}: unmapped region {s['region']}")
        base, size = REGIONS[s["region"]]
        if s["dst"] >= size:
            continue                                   # e.g. the namco timing PROM
        if s["dst"] + s["len"] > size:
            raise SystemExit(f"{setname}: {s['name']} overruns {s['region']}")
        a = base + s["dst"]
        out = [o for o in out if not (a <= o["addr"] and o["addr"] + o["len"] <= a + s["len"])]   # later load wins
        out.append(dict(s, addr=a))
    out.sort(key=lambda s: s["addr"])
    for a, b in zip(out, out[1:]):
        assert a["addr"] + a["len"] <= b["addr"], f"{setname}: overlap {a['name']} / {b['name']}"
    return out


def whole_file(seg, segs):
    """True when this segment is the file's only load (no ROM_CONTINUE pieces)."""
    return sum(1 for s in segs if s["name"] == seg["name"] and s["crc"] == seg["crc"]) == 1 and seg["src"] == 0

# ---------------------------------------------------------------- inputs -> MRA

def input_config(g, ports):
    """-> (idle bytes, dip list, input map, 4-way, P1 button names)."""
    idle, dips, imap, fourway, buttons = [], [], [0] * 32, False, {}
    for p, tag in enumerate(PORTS):
        fields = ports.get(tag)
        if fields is None:
            idle.append(0xFF)
            continue
        level = 0xFF
        for f in fields:
            level = (level & ~f["mask"]) | (f["default"] & f["mask"])
            if f["kind"] == "dip":
                lo = (f["mask"] & -f["mask"]).bit_length() - 1
                hi = f["mask"].bit_length() - 1
                if f["mask"] != ((1 << (hi + 1)) - (1 << lo)):
                    raise SystemExit(f'{g["name"]}: non-contiguous DIP {f["name"]} mask {f["mask"]:#x}')
                vals = [v >> lo for v, _ in f["settings"]]
                ids = ",".join(n.replace(",", ";") for _, n in f["settings"])
                bits = f"{p * 8 + lo}" if lo == hi else f"{p * 8 + lo},{p * 8 + hi}"
                seq = vals == list(range(len(vals))) and len(vals) == 1 << (hi - lo + 1)
                dips.append((f["name"], bits, ids, None if seq else ",".join(str(v) for v in vals)))
            elif f["kind"] == "input":
                t, pl = f["type"], f["player"]
                key = (t, pl if t.startswith(("JOYSTICK", "BUTTON")) else 0)
                if key not in CTL:
                    raise SystemExit(f'{g["name"]}: unmapped input {t} player {pl} in {tag}')
                if f["mask"] & (f["mask"] - 1):
                    raise SystemExit(f'{g["name"]}: multi-bit input {t} in {tag}')
                imap[p * 8 + f["mask"].bit_length() - 1] = CTL[key]
                fourway |= f["fourway"]
                if t.startswith("BUTTON") and pl == 1:
                    buttons[int(t[6:])] = f["name"] or ("Fire" if t == "BUTTON1" else f"Button {t[6:]}")
        idle.append(level & 0xFF)
    return idle, dips, imap, fourway, buttons


def hiscore_xml(g):
    return ""


def mra(g, games, segs, build_inputs):
    variant = SUPPORTED[(g["machine"], g["init"])]
    idle, dips, imap, fourway, buttons = input_config(g, build_inputs(g["inputs"]))
    flags = (F_4WAY if fourway else 0) | (F_VERT if g["rot"] in ("ROT90", "ROT270") else 0) | \
            (F_ROT90 if g["rot"] == "ROT90" else 0)
    nbtn = max(buttons) if buttons else 0
    names = ",".join([buttons.get(i, "Not Used") for i in range(1, 5)] + ["Coin", "Start 1P", "Start 2P", "Pause"])
    parent = g["parent"] or g["name"]
    zipname = f'{g["name"]}.zip' + (f'|{g["parent"]}.zip' if g["parent"] else "")
    rotation = {"ROT0": "horizontal", "ROT270": "vertical (ccw)", "ROT90": "vertical (cw)"}[g["rot"]]
    bootleg = "yes" if "bootleg" in g["manuf"].lower() or "hack" in g["desc"].lower() else "no"
    top = games.get(parent, g)                         # parent may live in another driver (suprglob: epos)
    series, category = SERIES_BY_PARENT.get(parent, (title_case(clean_title(top["desc"])), "Maze"))
    region = next((r for w, r in REGION_WORDS if w in g["desc"]), "World")

    lines = []
    pos = 0
    for s in segs:
        if s["addr"] > pos:
            lines.append(f'        <part repeat="0x{s["addr"] - pos:X}">00</part>')
        if whole_file(s, segs):
            lines.append(f'        <part crc="{s["crc"]}" name="{s["name"]}"/>')
        else:
            lines.append(f'        <part crc="{s["crc"]}" name="{s["name"]}" offset="0x{s["src"]:X}" length="0x{s["len"]:X}"/>')
        pos = s["addr"] + s["len"]

    dip_lines = "\n".join(f'        <dip name="{n}" bits="{b}" ids="{i}"' + (f' values="{v}"' if v else "") + "/>"
                          for n, b, i, v in dips)
    cfg = [variant, flags] + [0] * 14 + imap
    cfg_rows = "\n".join("            " + " ".join(f"{b:02X}" for b in cfg[i:i + 16]) for i in range(0, len(cfg), 16))
    return f"""<misterromdescription>
    <name>{display_name(g)}</name>
    <region>{region}</region>
    <homebrew>no</homebrew>
    <bootleg>{bootleg}</bootleg>
    <version></version>
    <alternative></alternative>
    <platform></platform>
    <series>{series}</series>
    <year>{g["year"]}</year>
    <manufacturer>{g["manuf"]}</manufacturer>
    <category>{category}</category>

    <setname>{g["name"]}</setname>
    <parent>{parent}</parent>
    <mameversion>{MAME_VERSION}</mameversion>
    <rbf>{RBF}</rbf>
    <about></about>

    <resolution>15kHz</resolution>
    <rotation>{rotation}</rotation>
    <flip>yes</flip>

    <players>2 (alternating)</players>
    <joystick>{"4-way" if fourway else "8-way"}</joystick>
    <special_controls></special_controls>
    <num_buttons>{nbtn}</num_buttons>
    <buttons names="{names}" default="A,Y,B,X,Select,Start,R,L"/>

    <switches default="{",".join(f"{b:02X}" for b in idle)}">
{dip_lines}
    </switches>

    <!-- Index 0: CPU 0x0000, gfx 0x10000, PROMs 0x14000, waveform PROM 0x14400 -->
    <rom index="0" md5="none" zip="{zipname}">
{chr(10).join(lines)}
    </rom>

    <!-- Index 1: board variant, flags, input map (see Arcade-Pacman.sv) -->
    <rom index="1">
        <part>
{cfg_rows}
        </part>
    </rom>
{hiscore_xml(g)}
    <remark>{remark(g)}</remark>
    <mratimestamp>20260928000000</mratimestamp>
</misterromdescription>
"""


SMALL_WORDS = {"a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs"}


def title_case(text):
    """Capitalise each word, keep acronyms (US, II, PCB), leave small words lower unless first."""
    out = []
    for i, word in enumerate(re.split(r"(\s+|[()/,-])", text)):
        if word and word[0].isalpha() and (i == 0 or word.lower() not in SMALL_WORDS):
            word = word[0].upper() + word[1:]
        out.append(word)
    return "".join(out)


def clean_title(desc):
    """Parent title: the description without its trailing parenthesised qualifiers."""
    return re.sub(r"(\s*\([^()]*\))+$", "", desc).strip()


def display_name(g):
    return title_case(clean_title(g["desc"]) if g["parent"] is None else g["desc"])


def remark(g):
    """'Title (Maker)', without repeating a maker the title already names."""
    m = re.fullmatch(r'bootleg \((.+)\)', g["manuf"])
    maker = f"{m.group(1)} bootleg" if m else g["manuf"]
    desc = title_case(g["desc"])
    return desc if maker.lower() in g["desc"].lower() else f"{desc} ({title_case(maker)})"


def safe(name):
    return re.sub(r'\s*/\s*', " - ", re.sub(r'[\\:*?"<>|]', "-", name))


def out_path(root, g, games):
    if g["parent"] is None:
        return root / f"{safe(display_name(g))}.mra"
    parent_title = display_name(games[g["parent"]]) if g["parent"] in games else title_case(clean_title(g["desc"]))
    return root / "_alternatives" / f"_{safe(parent_title)}" / f"{safe(display_name(g))}.mra"


def main():
    src = Path(sys.argv[1]).read_text()
    out_dir = Path(sys.argv[2])
    games = parse_games(src)
    build_inputs = parse_inputs(src)
    names = sys.argv[3:] or [n for n, g in games.items() if (g["machine"], g["init"]) in SUPPORTED]
    for name in names:
        g = games[name]
        if (g["machine"], g["init"]) not in SUPPORTED:
            raise SystemExit(f'{name}: board {g["machine"]} / {g["init"]} not implemented')
        segs = place(parse_roms(src, name), name)
        path = out_path(out_dir, g, games)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(mra(g, games, segs, build_inputs))
        print(f'{name:12s} {path.relative_to(out_dir)}')


if __name__ == "__main__":
    main()
