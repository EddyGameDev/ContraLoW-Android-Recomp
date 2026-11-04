#!/usr/bin/env python3
"""On-device test driver for the Contra LoW select-player fix (debug server).

Commands (first arg):
  ping                     liveness
  shot [name]              screenshot_file -> adb pull -> prints local path
  pad                      pad_status
  press BTN [frames] [gap] append one route step (press) + idle gap, then start
  route JSON               append raw steps [[frames,buttons],...] then start
  stop                     input_route_stop
  hle [tail] [fn]          hle_dump (optionally filter fn hex)
  frame                    get_frame
  runto N                  run_to_frame N
  raw JSON                 send a raw command json
BTN names: start cross circle triangle square up down left right l1 r1 l2 r2
Pad word is active-low (idle 0xFFFF; pressing clears the bit).
"""
import json, socket, subprocess, sys, os

HOST, PORT = "127.0.0.1", 4370
ADB = r"F:\tools\android-sdk\platform-tools\adb.exe"
PULL_DIR = r"C:\Users\dariu\AppData\Local\Temp\opencode\clow_shots"
SEQ = 100

BITS = {
    "select": 0x0001, "l3": 0x0002, "r3": 0x0004, "start": 0x0008,
    "up": 0x0010, "right": 0x0020, "down": 0x0040, "left": 0x0080,
    "l2": 0x0100, "r2": 0x0200, "l1": 0x0400, "r1": 0x0800,
    "triangle": 0x1000, "circle": 0x2000, "cross": 0x4000, "square": 0x8000,
}

def send(cmd, wait=60.0):
    s = socket.create_connection((HOST, PORT), timeout=wait)
    s.settimeout(wait)
    s.sendall((json.dumps(cmd) + "\n").encode())
    buf = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
            if b"\n" in buf:
                break
    except socket.timeout:
        pass
    s.close()
    return buf.decode(errors="replace")

def next_id():
    global SEQ
    SEQ += 1
    return SEQ

def mask(*names):
    m = 0
    for n in names:
        m |= BITS[n]
    return 0xFFFF & ~m & 0xFFFF

def shot(name="shot"):
    os.makedirs(PULL_DIR, exist_ok=True)
    dev = f"{name}.png"   # relative = app files dir (runtime chdr's there)
    out = send({"id": next_id(), "cmd": "screenshot_file", "path": dev})
    print("srv:", out.strip()[:200])
    if '"ok":true' not in out:
        return
    # adb can't read app-private files; stream them out byte-safe via run-as
    # cat in exec-out mode (powerShell text redirection corrupts binaries).
    local = os.path.join(PULL_DIR, f"{name}.png")
    subprocess.run(["cmd", "/c", f'{ADB} exec-out run-as com.psxrecomp.contralow cat files/{dev} > "{local}"'],
                   capture_output=True)
    n = os.path.getsize(local) if os.path.isfile(local) else 0
    print("pulled:", local, n, "bytes")

def press(btn, frames=8, gap=20):
    steps = [[frames, mask(btn)], [gap, 0xFFFF]]
    return route(steps)

def route(steps):
    for f, b in steps:
        out = send({"id": next_id(), "cmd": "input_route_append",
                    "frames": int(f), "buttons": int(b)})
        if '"ok":true' not in out.replace(" ", ""):
            print("append err:", out.strip()[:200])
            return out
    out = send({"id": next_id(), "cmd": "input_route_start"})
    print("route:", out.strip()[:200])
    return out

def hle(tail=40, fn=None):
    cmd = {"id": next_id(), "cmd": "hle_dump", "tail": tail}
    if fn is not None:
        cmd["fn"] = int(fn, 16) if isinstance(fn, str) else fn
    out = send(cmd, wait=90.0)
    print(out[:6000])
    return out

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "ping"
    if what == "ping":
        print(send({"id": 1, "cmd": "ping"}))
    elif what == "shot":
        shot(sys.argv[2] if len(sys.argv) > 2 else "shot")
    elif what == "pad":
        print(send({"id": next_id(), "cmd": "pad_status"}))
    elif what == "press":
        btn = sys.argv[2]
        f = int(sys.argv[3]) if len(sys.argv) > 3 else 8
        g = int(sys.argv[4]) if len(sys.argv) > 4 else 20
        press(btn, f, g)
    elif what == "route":
        route(json.loads(sys.argv[2]))
    elif what == "stop":
        print(send({"id": next_id(), "cmd": "input_route_stop"}))
    elif what == "hle":
        hle(int(sys.argv[2]) if len(sys.argv) > 2 else 40,
            sys.argv[3] if len(sys.argv) > 3 else None)
    elif what == "frame":
        print(send({"id": next_id(), "cmd": "get_frame"}))
    elif what == "runto":
        print(send({"id": next_id(), "cmd": "run_to_frame",
                    "frame": int(sys.argv[2])}, wait=120.0)[:400])
    elif what == "raw":
        cmd = json.loads(sys.argv[2])
        cmd.setdefault("id", next_id())
        print(send(cmd, wait=120.0)[:2000])
