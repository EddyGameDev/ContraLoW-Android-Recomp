#!/usr/bin/env python3
"""Find which ISO9660 file contains a given raw-bin offset / user-data offset,
extract it, and scan for 32-bit words. Raw 2352-byte sector image assumed
(MODE2 Form1: user data at +24), with MODE1 (+16) auto-detect."""
import os
import struct
import sys

BIN = r"F:\psx\ContraLoWRecomp\disc\Contra - Legacy of War (USA) (Track 01).bin"
OUT_DIR = r"C:\Users\dariu\AppData\Local\Temp\opencode\clow_extract"

SECTOR = 2352


class Raw:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.data_off = self.detect_data_off()

    def detect_data_off(self):
        self.f.seek(0)
        s = self.f.read(16)
        if s[0] == 0 and all(b == 0xFF for b in s[1:11]) and s[11] == 0:
            self.f.seek(15)
            mode = self.f.read(1)[0]
            return 24 if mode == 2 else 16
        return 0  # plain 2048 image

    def user_read(self, lba, count):
        self.f.seek(lba * SECTOR + self.data_off)
        return self.f.read(count)

    def user_write_at_off(self, user_off, data):
        """Write bytes into the image at a user-data offset (for extraction we read instead)."""
        raise NotImplementedError

    def user_bytes(self, user_off, length):
        out = bytearray()
        while length > 0:
            lba, off = divmod(user_off, 2048)
            n = min(2048 - off, length)
            self.f.seek(lba * SECTOR + self.data_off + off)
            out += self.f.read(n)
            user_off += n
            length -= n
        return bytes(out)


def parse_dir(raw, lba, size, path, files, depth=0):
    data = raw.user_bytes(lba * 2048, size)
    i = 0
    while i < len(data):
        rec_len = data[i]
        if rec_len == 0:
            # advance to next sector boundary
            i = (i // 2048 + 1) * 2048
            if i >= len(data):
                break
            continue
        rec = data[i:i + rec_len]
        ext_lba = struct.unpack_from("<I", rec, 2)[0]
        ext_size = struct.unpack_from("<I", rec, 10)[0]
        flags = rec[25]
        name_len = rec[32]
        name = rec[33:33 + name_len]
        if name in (b"\x00", b"\x01"):
            i += rec_len
            continue
        nm = name.decode("ascii", "replace").split(";")[0]
        if flags & 2:  # directory
            if depth < 6:
                parse_dir(raw, ext_lba, ext_size, path + "/" + nm, files, depth + 1)
        else:
            files.append((path + "/" + nm, ext_lba, ext_size))
        i += rec_len
    return files


def main():
    target_user = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x21ECCC
    raw = BIN and Raw(BIN)
    print(f"data_off={raw.data_off}")
    pvd = raw.user_bytes(16 * 2048, 2048)
    if pvd[1:6] != b"CD001":
        print("no PVD at LBA16"); sys.exit(1)
    root = pvd[156:156 + 34]
    root_lba = struct.unpack_from("<I", root, 2)[0]
    root_size = struct.unpack_from("<I", root, 10)[0]
    files = parse_dir(raw, root_lba, root_size, "", [])
    print(f"{len(files)} files")
    hit = None
    for name, lba, size in files:
        start = lba * 2048
        if start <= target_user < start + size:
            hit = (name, lba, size)
        # print bigger files for context
    for name, lba, size in sorted(files, key=lambda x: x[1]):
        mark = "  <== TARGET" if hit and (name, lba, size) == hit else ""
        print(f"LBA {lba:>6} size {size:>9}  {name}{mark}")
    if not hit:
        print("no file contains target offset"); return
    name, lba, size = hit
    os.makedirs(OUT_DIR, exist_ok=True)
    outname = os.path.join(OUT_DIR, os.path.basename(name).replace("/", "_"))
    data = raw.user_bytes(lba * 2048, size)
    with open(outname, "wb") as f:
        f.write(data)
    print(f"extracted {name} lba={lba} size={size} -> {outname}")
    print(f"target user offset 0x{target_user:X} = file offset 0x{target_user - lba * 2048:X}")


if __name__ == "__main__":
    main()
