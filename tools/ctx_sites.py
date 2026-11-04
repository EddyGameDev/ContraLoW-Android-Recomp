#!/usr/bin/env python3
"""Dump disassembly context around every jal 0x80051510 (A0 memset trampoline) site."""
import struct
import sys

sys.path.insert(0, r"F:\psx\ContraLoWRecomp\tools")
from mipsdis import disasm, exe_image, addr_to_off

SITES = [
    ("OVER8", r"C:\Users\dariu\AppData\Local\Temp\opencode\clow_extract\OVER8.OVL", 0x800FE588, 0x800EA050),
    ("OVER8", r"C:\Users\dariu\AppData\Local\Temp\opencode\clow_extract\OVER8.OVL", 0x800FFD14, 0x800EA050),
    ("EXE", r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88", 0x8002CDF8, None),
    ("EXE", r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88", 0x8002CE80, None),
    ("EXE", r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88", 0x8002CE94, None),
    ("EXE", r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88", 0x80032A78, None),
    ("EXE", r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88", 0x80032A88, None),
    ("EXE", r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88", 0x8004F930, None),
    ("EXE", r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88", 0x8004FF68, None),
    ("EXE", r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88", 0x80056808, None),
]

BACK = 20 * 4   # insns of context before the jal
FWD = 6 * 4     # after (incl. delay slot)

for tag, path, site, base in SITES:
    data = open(path, "rb").read()
    if base is None:
        h, payload = exe_image(path)
        off = addr_to_off(site, h, len(payload))
    else:
        off = site - base
    if off is None or off < 0 or off + FWD > len(data):
        print(f"=== {tag} site 0x{site:08X}: offset unmappable ===")
        continue
    start = max(0, off - BACK)
    print(f"=== {tag} site 0x{site:08X} (file 0x{off:X}) ===")
    print(disasm(data[start:off + FWD], site - (off - start)))
    print()
