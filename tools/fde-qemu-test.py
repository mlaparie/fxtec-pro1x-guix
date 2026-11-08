#!/usr/bin/env python3
"""Boot a userdata image from scripts/flash-encrypted.sh in QEMU.

  fde-qemu-test.py USERDATA.IMG PASSPHRASE [--disk-gib N] [--entry N] [--keep]
  fde-qemu-test.py --plain ROOT.EXT4 [--disk-gib N] [--entry N] [--keep]

Puts the image in a GPT partition named "userdata" on a sparse virtual disk,
reads the plain area the way U-Boot does (/boot/extlinux/extlinux.conf, entry
N), and boots that kernel and initrd on QEMU's "virt" machine, whose virtio and
PL011 drivers the phone's kernel has.  Types a wrong passphrase, then the right
one, then waits for SSH on localhost:2222 (root, ~/.ssh/pro1x-guix) and leaves
the machine running until Ctrl-C or SIGTERM.  Serial output: DISK.console.log.
With --plain, the unencrypted layout: the same system must boot without asking.

What this covers: the initrd's unlock, retry, resize, Shepherd, deploys.  What
it does not: U-Boot, UFS timing, the panel, the keyboard, every service that
needs the phone's hardware.  Needs qemu-system-aarch64, sfdisk, debugfs.

The disk stays next to the image (DISK.raw), so a second run with --keep boots
what a deploy left there; without it the disk is made anew.
"""
import argparse
import fcntl
import os
import pathlib
import re
import socket
import subprocess
import sys
import threading
import struct
import time

BOOT_CONF = "/boot/extlinux/extlinux.conf"
MIB = 1024 * 1024


def run(*args, **kw):
    return subprocess.run(args, check=True, **kw)


FICLONERANGE = 0x4020940D


def make_disk(image, disk, gib):
    size = gib * 1024 * MIB
    with open(disk, "wb") as f:
        f.truncate(size)
    run("sfdisk", "-q", str(disk),
        input=b"label: gpt\nstart=2048, name=userdata\n")
    # On btrfs or XFS, clone the image's blocks (no space taken until the
    # machine writes); elsewhere, copy.  The clone is whole blocks, the tail
    # copied after it.
    length = image.stat().st_size // 4096 * 4096
    try:
        with open(image, "rb") as src, open(disk, "r+b") as dst:
            fcntl.ioctl(dst.fileno(), FICLONERANGE,
                        struct.pack("qQQQ", src.fileno(), 0, length, MIB))
    except OSError:
        length = 0
    run("dd", f"if={image}", f"of={disk}", "bs=4096", f"skip={length // 4096}",
        f"seek={(MIB + length) // 4096}", "conv=notrunc,sparse", "status=none")


def debugfs_read(disk, path, out=None, area_mib=512):
    """Read PATH from the file system that starts at 1 MiB on DISK."""
    plain = disk.with_suffix(".plain")
    run("dd", f"if={disk}", f"of={plain}", "bs=1M", "skip=1", f"count={area_mib}", "status=none")
    if out:
        run("debugfs", "-R", f"dump {path} {out}", str(plain),
            stderr=subprocess.DEVNULL)
        data = None
    else:
        data = subprocess.run(["debugfs", "-R", f"cat {path}", str(plain)],
                              check=True, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL).stdout.decode()
    plain.unlink()
    return data


def boot_entry(conf, number):
    """The Nth LABEL block's KERNEL, INITRD and APPEND, as U-Boot takes them."""
    blocks = re.split(r"(?m)^\s*LABEL\s", conf)[1:]
    block = blocks[number - 1]
    field = lambda name: re.search(rf"(?m)^\s*{name}\s+(.*)$", block).group(1).strip()
    return field("KERNEL"), field("INITRD"), field("APPEND")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", type=pathlib.Path)
    ap.add_argument("passphrase", nargs="?")
    ap.add_argument("--plain", action="store_true")
    ap.add_argument("--disk-gib", type=int, default=24)
    ap.add_argument("--entry", type=int, default=1)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--initrd", help="boot this initrd instead of the plain area's")
    args = ap.parse_args()
    if not args.plain and args.passphrase is None:
        ap.error("the passphrase is needed without --plain")

    disk = args.image.with_suffix(".raw")
    if not (args.keep and disk.exists()):
        make_disk(args.image, disk, args.disk_gib)

    area_mib = args.image.stat().st_size // MIB + 1 if args.plain else 512
    conf = debugfs_read(disk, BOOT_CONF, area_mib=area_mib)
    kernel, initrd, append = boot_entry(conf, args.entry)
    print(f"entry {args.entry}: {kernel}\n  {initrd}\n  {append}", flush=True)
    work = disk.with_suffix(".boot")
    work.mkdir(exist_ok=True)
    debugfs_read(disk, kernel, work / "Image", area_mib)
    debugfs_read(disk, initrd, work / "initrd", area_mib)
    for f in ("Image", "initrd"):
        if not (work / f).stat().st_size:
            sys.exit(f"cannot read {f} from the plain area: U-Boot could not either")

    append = re.sub(r"\b(console=\S+|fbcon=\S+|quiet)\s*", "", append) + " console=ttyAMA0"
    log = open(disk.with_suffix(".console.log"), "wb")
    qemu = subprocess.Popen(
        ["qemu-system-aarch64", "-M", "virt", "-cpu", "max", "-smp", "4", "-m", "4G",
         "-nographic", "-kernel", str(work / "Image"), "-initrd", args.initrd or str(work / "initrd"),
         "-append", append,
         "-drive", f"file={disk},if=none,id=d,format=raw",
         "-device", "virtio-blk-pci,drive=d",
         "-netdev", "user,id=n,hostfwd=tcp:127.0.0.1:2222-:22",
         "-device", "virtio-net-pci,netdev=n"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    prompts = []
    buffer = bytearray()

    def reader():
        while True:
            chunk = qemu.stdout.read1(4096)
            if not chunk:
                return
            log.write(chunk)
            log.flush()
            buffer.extend(chunk)
            if re.search(rb"Enter passphrase for [^\n]*: ?$", bytes(buffer[-120:])):
                prompts.append(time.time())
                del buffer[:]

    threading.Thread(target=reader, daemon=True).start()

    def wait_for_prompt(count, timeout):
        end = time.time() + timeout
        while len(prompts) < count:
            if time.time() > end or qemu.poll() is not None:
                sys.exit(f"no passphrase prompt {count}; see {log.name}")
            time.sleep(0.5)

    def send(text):
        qemu.stdin.write(text.encode() + b"\r")
        qemu.stdin.flush()

    try:
        if not args.plain:
            wait_for_prompt(1, 900)
            print("prompt 1: sending a wrong passphrase", flush=True)
            send("wrong")
            wait_for_prompt(2, 300)
            print("prompt 2: asked again; sending the right one", flush=True)
            send(args.passphrase)
        unlock_from = time.time()
        end = time.time() + 1800
        while time.time() < end and qemu.poll() is None:
            try:
                with socket.create_connection(("127.0.0.1", 2222), 3) as s:
                    s.settimeout(10)
                    if s.recv(16).startswith(b"SSH-"):
                        print(f"SSH up {time.time() - unlock_from:.0f} s after the passphrase",
                              flush=True)
                        break
            except OSError:
                pass
            time.sleep(5)
        else:
            sys.exit(f"SSH did not come up; see {log.name}")
        if args.plain and prompts:
            sys.exit(f"the plain layout asked for a passphrase; see {log.name}")
        print("READY", flush=True)
        qemu.wait()
    finally:
        if qemu.poll() is None:
            qemu.terminate()


if __name__ == "__main__":
    main()
