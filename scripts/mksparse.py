#!/usr/bin/env python3
"""Split a raw partition image into Android sparse images under a size limit.

  mksparse.py IMAGE PREFIX [MAX_BYTES]

Writes PREFIX.0.simg, PREFIX.1.simg…, one per line on stdout.  Each part
covers the whole partition: its share of the image as raw chunks (zero
blocks as fill chunks), the rest "don't care", so flashing them one after the
other with fastboot writes the image.  MAX_BYTES defaults to 512 MiB, well
under the 768 MiB the stock bootloader reports (max-download-size).

Why: fastboot 7.1.2 (Guix's) splits raw images itself, but read the
encrypted userdata.img as empty (libsparse's import gave a length of -1)
and sent 0 KB, 2026-11-05; the CI rootfs.img it split fine.
"""
import struct
import sys

BLOCK = 4096
MAGIC = 0xED26FF3A
RAW, FILL, DONT_CARE = 0xCAC1, 0xCAC2, 0xCAC3
ZERO = bytes(BLOCK)


def header(total_blocks, chunks):
    return struct.pack("<IHHHHIIII", MAGIC, 1, 0, 28, 12, BLOCK,
                       total_blocks, chunks, 0)


def chunk(kind, blocks, data_bytes):
    return struct.pack("<HHII", kind, 0, blocks, 12 + data_bytes)


def main():
    image, prefix = sys.argv[1], sys.argv[2]
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 512 * 1024 * 1024
    with open(image, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        if size % BLOCK:
            sys.exit(f"{image}: size not a multiple of {BLOCK}")
        total = size // BLOCK
        f.seek(0)
        block, part = 0, 0
        while block < total:
            # One part: don't care up to BLOCK, then runs until the limit.
            body, chunks, start = [], 0, block
            if start:
                body.append(chunk(DONT_CARE, start, 0)); chunks += 1
            used = 28 + 12 * 2
            while block < total and used < limit - BLOCK - 24:
                data = f.read(BLOCK)
                if data == ZERO:
                    n = 1
                    while block + n < total:
                        nxt = f.read(BLOCK)
                        if nxt != ZERO:
                            f.seek(-BLOCK, 1)
                            break
                        n += 1
                    body.append(chunk(FILL, n, 4) + bytes(4)); chunks += 1
                    used += 16
                    block += n
                else:
                    run = [data]
                    while (block + len(run) < total and
                           used + 12 + BLOCK * (len(run) + 1) < limit - 24):
                        nxt = f.read(BLOCK)
                        if nxt == ZERO:
                            f.seek(-BLOCK, 1)
                            break
                        run.append(nxt)
                    body.append(chunk(RAW, len(run), BLOCK * len(run)))
                    body.append(b"".join(run)); chunks += 1
                    used += 12 + BLOCK * len(run)
                    block += len(run)
            if block < total:
                body.append(chunk(DONT_CARE, total - block, 0)); chunks += 1
            name = f"{prefix}.{part}.simg"
            with open(name, "wb") as out:
                out.write(header(total, chunks))
                for b in body:
                    out.write(b)
            print(name, flush=True)
            part += 1


if __name__ == "__main__":
    main()
