#!/usr/bin/env python3
"""Build a small concatenated initramfs overlay for Taiko Ubuntu v7."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, "/workspace/tools")
from build_taiko_platform_v5 import Entry, align, pack_newc, parse_newc  # noqa: E402

ROOT = Path("/workspace")
MAGISKBOOT = ROOT / "scratch/tablet-rom/native-linux/magisk31-x86_64-libmagiskboot.so"
OUT = ROOT / "outputs/Taiko-Ubuntu-24.04/loader-v7"

LOADER = b"""#!/system/bin/sh
T=/system/bin/toybox
L(){ echo "<6>TAIKO_LINUX_V7:$*" >/dev/kmsg 2>/dev/null; }
P(){ L "PANIC $*";echo 3 >/proc/sys/kernel/panic;echo 1 >/proc/sys/kernel/sysrq;echo c >/proc/sysrq-trigger;while :;do :;done; }
$T mount -t proc proc /proc 2>/dev/null||:
$T mount -t sysfs sysfs /sys 2>/dev/null||:
$T mount -t devtmpfs devtmpfs /dev 2>/dev/null||:
$T mkdir -p /newroot /dev/pts
$T mount -t devpts devpts /dev/pts 2>/dev/null||:
L PID1
M=
while read m;do [ "$m" = mtk_wdt.ko ]||M="$M ${m%.ko}";done </lib/modules/modules.load
L modprobe-inicio
$T modprobe -a -d /lib/modules $M 2>/dev/kmsg
L "modprobe-fim rc=$?"
i=0
while [ $i -lt 5 ]&&[ ! -e /sys/class/block/sdc73/dev ];do i=$((i+1));$T sleep 1;done
[ -e /sys/class/block/sdc73/dev ]||P sdc73-ausente
IFS=: read A B </sys/class/block/sdc73/dev
[ -b /dev/sdc73 ]||$T mknod /dev/sdc73 b "$A" "$B"||P mknod
L "sdc73=$A:$B"
$T mount -t ext4 -o rw,noatime /dev/sdc73 /newroot||P mount-ext4
[ -x /newroot/sbin/init ]||P systemd-ausente
$T mkdir -p /newroot/var/log /newroot/proc /newroot/sys /newroot/dev /newroot/run/initramfs
echo ufs-mounted-v7 >/newroot/var/log/taiko-loader-stage
$T sync
L Ubuntu-montado
$T mount --move /proc /newroot/proc||P move-proc
$T mount --move /sys /newroot/sys||P move-sys
$T mount --move /dev /newroot/dev||P move-dev
$T mount --bind /newroot /newroot||P bind
cd /newroot||P cd
$T pivot_root . run/initramfs||P pivot
echo systemd-v7 >/var/log/taiko-loader-stage
sync
echo '<6>TAIKO_LINUX_V7:systemd' >/dev/kmsg
exec /sbin/init
"""


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    entries = [
        Entry("p", 1, 0o100750, 0, 0, 1, 0, LOADER),
        Entry("dev/kmsg", 2, 0o020600, 0, 0, 1, 0, b"", rdevmajor=1, rdevminor=11),
        Entry("TRAILER!!!", 3, 0, 0, 0, 1, 0, b""),
    ]
    cpio = b"".join(pack_newc(e) for e in entries)
    cpio += b"\0" * (align(len(cpio), 512) - len(cpio))
    cpio_path = OUT / "taiko-linux-v7-overlay.cpio"
    lz4_path = OUT / "taiko-linux-v7-overlay.lz4"
    verify = OUT / "verify.cpio"
    cpio_path.write_bytes(cpio)
    subprocess.run([str(MAGISKBOOT), "compress=lz4_legacy", str(cpio_path), str(lz4_path)], check=True)
    subprocess.run([str(MAGISKBOOT), "decompress", str(lz4_path), str(verify)], check=True)
    if verify.read_bytes() != cpio:
        raise ValueError("legacy LZ4 round trip failed")
    verify.unlink()
    parsed = {e.name: e for e in parse_newc(cpio)}
    if parsed["p"].data != LOADER:
        raise ValueError("loader mismatch")
    report = {
        "cpio_size": len(cpio),
        "cpio_sha256": sha(cpio),
        "overlay_size": lz4_path.stat().st_size,
        "overlay_sha256": sha(lz4_path.read_bytes()),
        "loader_sha256": sha(LOADER),
        "method": "concatenated legacy-LZ4 initramfs; original platform fragment unchanged",
    }
    (OUT / "build.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
