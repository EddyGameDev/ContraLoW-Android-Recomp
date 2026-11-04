#!/usr/bin/env python3
"""Targeted disassembly for the a2-inheritance investigation."""
import sys

sys.path.insert(0, r"F:\psx\ContraLoWRecomp\tools")
from mipsdis import disasm, exe_image, addr_to_off

EXE = r"F:\psx\ContraLoWRecomp\disc\SLUS_002.88"
OVL = r"C:\Users\dariu\AppData\Local\Temp\opencode\clow_extract\OVER8.OVL"
OVL_BASE = 0x800EA050

h, payload = exe_image(EXE)


def exe_dump(va, ln):
    off = addr_to_off(va, h, len(payload))
    print(f"--- EXE 0x{va:08X} (+{ln:#x}) ---")
    print(disasm(payload[off:off + ln], va))
    print()


def ovl_dump(va, ln):
    off = va - OVL_BASE
    print(f"--- OVER8 0x{va:08X} (file 0x{off:X}, +{ln:#x}) ---")
    print(disasm(open(OVL, "rb").read()[off:off + ln], va))
    print()


# 1. The EXE function called just before the memset wrapper (a2 = [0x80100F64])
exe_dump(0x80044E40, 0xC0)

# 2. Full caller window around the memset-wrapper call site
ovl_dump(0x800FECF0, 0x1A0)

# 3. The interpreter "instruction guard" site from the report
ovl_dump(0x80100980, 0xC0)
