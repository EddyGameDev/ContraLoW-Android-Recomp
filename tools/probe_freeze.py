import json
import sys

sys.path.insert(0, r"F:\psx\ContraLoWRecomp\tools")
from dbg import send

READS = [
    ("a0_dispatcher", 0x3554, 0x400),
    ("a0_vector_stub", 0x000000A0, 0x20),
    ("overlay_base", 0x800EA050, 0x40),
    ("glob_f64", 0x80100F60, 0x10),
    ("glob_ed8_ee8", 0x80100ED0, 0x20),
    ("glob_a88", 0x80100A88, 0x10),
    ("glob_e48_table", 0x80100E48, 0x20),
    ("memset_dst", 0x80100E0C, 0x20),
]

out = {}
for name, addr, ln in READS:
    resp = send({"id": 1, "cmd": "read_ram", "addr": f"0x{addr:X}", "len": ln}, wait=40.0)
    try:
        d = json.loads(resp)
    except Exception:
        print(name, "RAW:", resp[:200])
        continue
    hx = d.get("hex", "")
    out[name] = (addr, ln, hx)
    print(f"{name:16s} 0x{addr:08X} len {ln}: {hx[:160]}{'...' if len(hx) > 160 else ''}")

with open(r"F:\psx\ContraLoWRecomp\ram_read.hex", "a", encoding="utf-8") as f:
    for name, (addr, ln, hx) in out.items():
        f.write(f"# 0x{addr:X} len {ln}\n{hx}\n")
print("appended to ram_read.hex")
