#!/usr/bin/env python3
"""Follow the call tree from 0x80044CE0 to find the last a2 write (the real-HW
leftover that the 2-arg memset in OVER8 relies on)."""
import struct
import sys

sys.path.insert(0, r"F:\psx\ContraLoWRecomp\tools")
from mipsdis import disasm, exe_image, addr_to_off

EXE = r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88"
h, payload = exe_image(EXE)


def dump(va, ln=0x80):
    off = addr_to_off(va, h, len(payload))
    if off is None:
        print(f"0x{va:08X}: not in EXE")
        return
    print(f"--- 0x{va:08X} ---")
    print(disasm(payload[off:off + ln], va))
    print()


dump(0x80044B0C, 0x180)
