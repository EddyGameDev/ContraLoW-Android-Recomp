import socket, json, sys

HOST, PORT = "127.0.0.1", 4370

def send(cmd, wait=35.0):
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

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "ping"
    if what == "ping":
        print(send({"id": 1, "cmd": "ping"}))
    elif what == "bioscall":
        tail = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
        out = send({"id": 2, "cmd": "bioscall_dump", "tail": tail}, wait=40.0)
        open(r"F:\psx\ContraLoWRecomp\bioscall_ring.json", "w", encoding="utf-8").write(out)
        print(out[:300])
    elif what == "bioscallf":
        # args: table index tail outfile
        table = sys.argv[2]; idx = int(sys.argv[3])
        tail = int(sys.argv[4]) if len(sys.argv) > 4 else 65536
        outfn = sys.argv[5] if len(sys.argv) > 5 else r"F:\psx\ContraLoWRecomp\bioscall_filtered.json"
        out = send({"id": 2, "cmd": "bioscall_dump", "table": table, "index": idx, "tail": tail}, wait=40.0)
        open(outfn, "w", encoding="utf-8").write(out)
        print(out[:300])
    elif what == "read":
        addr = sys.argv[2]; ln = int(sys.argv[3]) if len(sys.argv) > 3 else 256
        out = send({"id": 4, "cmd": "read_ram", "addr": addr, "len": ln}, wait=40.0)
        d = json.loads(out)
        open(r"F:\psx\ContraLoWRecomp\ram_read.hex", "a", encoding="utf-8").write(
            f"# {addr} len {ln}\n{d.get('hex','')}\n")
        print("ok" if d.get("ok") else out[:200])
    elif what == "regs":
        print(send({"id": 5, "cmd": "get_registers"})[:2000])
