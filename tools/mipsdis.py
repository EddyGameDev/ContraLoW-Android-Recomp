#!/usr/bin/env python3
"""MIPS (PS1) disassembly helper using capstone.

Subcommands:
  dump <hexfile>              Disassemble ram_read.hex-style dumps (lines "# 0xADDR len" + hex)
  exe <file> <addr> <len>     Disassemble from a PS-X EXE image at a virtual address
  scan <file> <word> [--exe]  Find 32-bit word occurrences (e.g. jal target 0x0C03F95C)
  hdr <file>                  Print PS-X EXE header fields
"""
import argparse
import struct
import sys

from capstone import Cs, CS_ARCH_MIPS, CS_MODE_MIPS32, CS_MODE_LITTLE_ENDIAN

md = Cs(CS_ARCH_MIPS, CS_MODE_MIPS32 | CS_MODE_LITTLE_ENDIAN)
md.skipdata = True


def disasm(data: bytes, base: int) -> str:
    lines = []
    for ins in md.disasm(data, base):
        raw = ins.bytes.hex()
        lines.append(f"0x{ins.address:08X}: {raw:<8s}  {ins.mnemonic:<8s} {ins.op_str}")
    return "\n".join(lines)


def parse_dumps(path: str):
    """Parse ram_read.hex-style file: '# 0xADDR len' comment lines followed by a hex line."""
    dumps = []
    addr = None
    hexbuf = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                if addr is not None and hexbuf:
                    dumps.append((addr, bytes.fromhex("".join(hexbuf))))
                parts = line[1:].split()
                addr = int(parts[0], 16)
                hexbuf = []
            else:
                hexbuf.append(line)
    if addr is not None and hexbuf:
        dumps.append((addr, bytes.fromhex("".join(hexbuf))))
    return dumps


def exe_header(path: str):
    with open(path, "rb") as f:
        hdr = f.read(0x800)
    if hdr[0:8] != b"PS-X EXE":
        print("warning: not a PS-X EXE header", file=sys.stderr)
    pc0, gp0, t_addr, t_size, d_addr, d_size = struct.unpack_from("<6I", hdr, 0x10)
    b_addr, b_size = struct.unpack_from("<2I", hdr, 0x28)
    sp0, = struct.unpack_from("<I", hdr, 0x30)
    return {
        "pc0": pc0, "t_addr": t_addr, "t_size": t_size,
        "d_addr": d_addr, "d_size": d_size,
        "b_addr": b_addr, "b_size": b_size, "sp0": sp0,
    }


def exe_image(path: str):
    """Return (image_bytes, base_va) covering text+data payload, or None if split."""
    h = exe_header(path)
    with open(path, "rb") as f:
        f.seek(0x800)
        payload = f.read()
    return h, payload


def addr_to_off(va: int, h: dict, payload_len: int):
    """Map virtual address -> offset in payload (text then data contiguous)."""
    t_end = h["t_addr"] + h["t_size"]
    if h["t_addr"] <= va < t_end:
        return va - h["t_addr"]
    d_addr = h["d_addr"] or t_end
    if d_addr <= va < d_addr + h["d_size"]:
        return h["t_size"] + (va - d_addr)
    return None


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("dump")
    p.add_argument("hexfile")

    p = sub.add_parser("exe")
    p.add_argument("exefile")
    p.add_argument("addr", type=lambda s: int(s, 0))
    p.add_argument("length", type=lambda s: int(s, 0))

    p = sub.add_parser("scan")
    p.add_argument("file")
    p.add_argument("word", type=lambda s: int(s, 0))
    p.add_argument("--exe", action="store_true")

    p = sub.add_parser("hdr")
    p.add_argument("exefile")

    args = ap.parse_args()

    if args.cmd == "dump":
        for addr, data in parse_dumps(args.hexfile):
            print(f"=== dump 0x{addr:08X} len {len(data)} (end 0x{addr + len(data):08X}) ===")
            print(disasm(data, addr))
            print()

    elif args.cmd == "exe":
        h, payload = exe_image(args.exefile)
        off = addr_to_off(args.addr, h, len(payload))
        if off is None:
            print(f"address 0x{args.addr:08X} not within EXE image "
                  f"(text 0x{h['t_addr']:08X}+0x{h['t_size']:X}, data 0x{h['d_addr'] or (h['t_addr'] + h['t_size']):08X}+0x{h['d_size']:X})")
            sys.exit(1)
        print(disasm(payload[off:off + args.length], args.addr))

    elif args.cmd == "scan":
        pat = struct.pack("<I", args.word)
        if args.exe:
            h, payload = exe_image(args.file)
            base = h["t_addr"]
            idx = 0
            while True:
                i = payload.find(pat, idx)
                if i < 0:
                    break
                if i < h["t_size"]:
                    va = h["t_addr"] + i
                else:
                    d_addr = h["d_addr"] or (h["t_addr"] + h["t_size"])
                    va = d_addr + (i - h["t_size"])
                print(f"0x{va:08X}")
                idx = i + 1
        else:
            for addr, data in parse_dumps(args.file):
                idx = 0
                while True:
                    i = data.find(pat, idx)
                    if i < 0:
                        break
                    print(f"0x{addr + i:08X}")
                    idx = i + 1

    elif args.cmd == "hdr":
        h = exe_header(args.exefile)
        for k, v in h.items():
            print(f"{k} = 0x{v:08X}")


if __name__ == "__main__":
    main()
