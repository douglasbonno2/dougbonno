#!/usr/bin/env python3
"""Build the Taiko native Ubuntu platform ramdisk v5.

The loader replays the kernel-module order observed in a known-good Android
boot until the internal UFS disk is available, then pivots to the Ubuntu
filesystem already installed on userdata.
"""

from __future__ import annotations

import hashlib
import json
import re
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path


ROOT = Path("/workspace")
SOURCE_CPIO = ROOT / "analysis/taiko-loader-initrd-full/taiko-loader-initrd.dec"
ANDROID_DMESG = ROOT / "analysis/taiko-retain-20261107/dmesg.txt"
BUSYBOX = ROOT / "scratch/tablet-rom/native-linux/magisk31-arm64-v8a-libbusybox.so"
MAGISKBOOT = ROOT / "scratch/tablet-rom/native-linux/magisk31-x86_64-libmagiskboot.so"
OUT = ROOT / "outputs/Taiko-Ubuntu-24.04/loader-v5"


@dataclass
class Entry:
    name: str
    ino: int
    mode: int
    uid: int
    gid: int
    nlink: int
    mtime: int
    data: bytes
    devmajor: int = 0
    devminor: int = 0
    rdevmajor: int = 0
    rdevminor: int = 0
    check: int = 0


def align(value: int, boundary: int) -> int:
    return (value + boundary - 1) // boundary * boundary


def parse_newc(blob: bytes) -> list[Entry]:
    entries: list[Entry] = []
    pos = 0
    while pos < len(blob):
        while pos < len(blob) and blob[pos] == 0:
            pos += 1
        if pos == len(blob):
            break
        if blob[pos : pos + 6] not in (b"070701", b"070702"):
            raise ValueError(f"invalid newc header at {pos}")
        header = blob[pos : pos + 110]
        fields = [int(header[6 + i * 8 : 14 + i * 8], 16) for i in range(13)]
        (ino, mode, uid, gid, nlink, mtime, size, devmajor, devminor,
         rdevmajor, rdevminor, namesize, check) = fields
        name_start = pos + 110
        name = blob[name_start : name_start + namesize - 1].decode(
            "utf-8", "surrogateescape"
        )
        data_start = align(name_start + namesize, 4)
        data = blob[data_start : data_start + size]
        pos = align(data_start + size, 4)
        entries.append(
            Entry(name, ino, mode, uid, gid, nlink, mtime, data, devmajor,
                  devminor, rdevmajor, rdevminor, check)
        )
        if name == "TRAILER!!!":
            break
    if not entries or entries[-1].name != "TRAILER!!!":
        raise ValueError("newc trailer not found")
    return entries


def pack_newc(entry: Entry) -> bytes:
    name = entry.name.encode("utf-8", "surrogateescape") + b"\0"
    values = (
        entry.ino, entry.mode, entry.uid, entry.gid, entry.nlink, entry.mtime,
        len(entry.data), entry.devmajor, entry.devminor, entry.rdevmajor,
        entry.rdevminor, len(name), entry.check,
    )
    out = bytearray(b"070701" + b"".join(f"{v:08x}".encode() for v in values))
    out += name
    out += b"\0" * (align(len(out), 4) - len(out))
    out += entry.data
    out += b"\0" * (align(len(out), 4) - len(out))
    return bytes(out)


def sha(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def observed_module_order() -> list[tuple[str, str]]:
    pattern = re.compile(r"init: Loading module /lib/modules/([^ ]+) with args '(.*)'")
    result: list[tuple[str, str]] = []
    for line in ANDROID_DMESG.read_text(errors="replace").splitlines():
        match = pattern.search(line)
        if match:
            result.append((match.group(1), match.group(2)))
    if len(result) != 197 or len({name for name, _ in result}) != 197:
        raise ValueError("known-good Android module trace is incomplete")
    expected = {
        "ufs-mediatek-mod.ko": 13,
        "mtk_wdt.ko": 21,
        "reset-ti-syscon.ko": 131,
        "phy-mtk-ufs.ko": 132,
    }
    for name, position in expected.items():
        if result[position - 1][0] != name:
            raise ValueError(f"unexpected position for {name}")
    # UFS becomes operational immediately after phy-mtk-ufs. Later modules are
    # Android peripherals and are intentionally left for future Linux enablement.
    return result[:132]


LOADER = b"""#!/taiko/busybox sh
BB=/taiko/busybox
log(){ echo "<6>TAIKO_LINUX_V5: $*" > /dev/kmsg 2>/dev/null; }
fail(){ log "FALHA $*"; $BB sync; while :; do $BB sleep 5; done; }
$BB mount -t proc proc /proc 2>/dev/null || true
$BB mount -t sysfs sysfs /sys 2>/dev/null || true
$BB mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
$BB mkdir -p /dev/pts /newroot
$BB mount -t devpts devpts /dev/pts 2>/dev/null || true
[ -e /dev/kmsg ] || $BB mknod -m 600 /dev/kmsg c 1 11 2>/dev/null || true
log "PID1 confirmado; ordem Android"
c=0
errors=0
while IFS='|' read -r m args; do
  [ -n "$m" ] || continue
  c=$((c+1))
  if [ "$m" = mtk_wdt.ko ]; then
    log "watchdog omitido na posicao $c"
    continue
  fi
  if [ -n "$args" ]; then
    $BB insmod "/lib/modules/$m" $args 2>/dev/null
  else
    $BB insmod "/lib/modules/$m" 2>/dev/null
  fi
  rc=$?
  if [ "$rc" -ne 0 ]; then
    errors=$((errors+1))
    log "ERRO modulo=$c:$m rc=$rc"
  fi
  [ $((c%10)) -eq 0 ] && log "modulos=$c erros=$errors"
done < /taiko/modules.ufs-order
log "fim modulos=$c erros=$errors"
i=0
while [ "$i" -lt 10 ] && [ ! -e /sys/class/block/sdc73/dev ]; do
  i=$((i+1))
  $BB sleep 1
done
[ -e /sys/class/block/sdc73/dev ] || fail "sdc73 ausente"
IFS=: read -r MAJ MIN < /sys/class/block/sdc73/dev
[ -b /dev/sdc73 ] || $BB mknod -m 600 /dev/sdc73 b "$MAJ" "$MIN" 2>/dev/null || fail "mknod sdc73"
log "sdc73 presente dev=$MAJ:$MIN"
$BB mount -t ext4 -o rw,noatime /dev/sdc73 /newroot 2>/dev/null || fail "mount ext4"
[ -x /newroot/sbin/init ] || fail "systemd ausente"
$BB mkdir -p /newroot/var/log
echo 'ufs-mounted-v5' > /newroot/var/log/taiko-loader-stage
log "Ubuntu montado; iniciando systemd"
$BB mkdir -p /newroot/proc /newroot/sys /newroot/dev /newroot/run/initramfs
$BB mount --move /proc /newroot/proc 2>/dev/null || fail "move proc"
$BB mount --move /sys /newroot/sys 2>/dev/null || fail "move sys"
$BB mount --move /dev /newroot/dev 2>/dev/null || fail "move dev"
$BB mount --bind /newroot /newroot 2>/dev/null || fail "bind root"
cd /newroot || fail "cd root"
$BB pivot_root . run/initramfs 2>/dev/null || fail "pivot root"
echo 'systemd-v5' > /var/log/taiko-loader-stage
echo '<6>TAIKO_LINUX_V5: executando systemd' > /dev/kmsg 2>/dev/null
exec /sbin/init
"""


def main() -> None:
    source = SOURCE_CPIO.read_bytes()
    entries = parse_newc(source)
    names = {entry.name for entry in entries}
    for name in ("p", "taiko", "taiko/busybox", "taiko/modules.ufs-order"):
        if name in names:
            raise ValueError(f"source already contains {name}")

    order = observed_module_order()
    module_paths = {entry.name for entry in entries if entry.name.endswith(".ko")}
    missing = [name for name, _ in order if f"lib/modules/{name}" not in module_paths]
    if missing:
        raise ValueError(f"modules missing from platform ramdisk: {missing}")
    order_blob = "".join(f"{name}|{args}\n" for name, args in order).encode()

    # The Linux PID 1 path never starts Android adbd. Removing this platform
    # copy makes room for the static BusyBox without growing the signed
    # vendor_boot structured area. TWRP has its own recovery fragment and is
    # verified separately by the installer.
    adbd = [entry for entry in entries if entry.name == "system/bin/adbd"]
    if len(adbd) != 1 or not adbd[0].data.startswith(b"\x7fELF"):
        raise ValueError("expected platform adbd was not found")
    entries = [entry for entry in entries if entry.name != "system/bin/adbd"]

    trailer = entries.pop()
    next_ino = max(entry.ino for entry in entries) + 1
    additions = [
        Entry("taiko", next_ino, 0o040755, 0, 0, 1, 0, b""),
        Entry("taiko/busybox", next_ino + 1, 0o100750, 0, 0, 1, 0, BUSYBOX.read_bytes()),
        Entry("taiko/modules.ufs-order", next_ino + 2, 0o100600, 0, 0, 1, 0, order_blob),
        Entry("p", next_ino + 3, 0o100750, 0, 0, 1, 0, LOADER),
    ]
    if "dev/kmsg" not in names:
        additions.append(
            Entry("dev/kmsg", next_ino + 4, 0o020600, 0, 0, 1, 0, b"", rdevmajor=1, rdevminor=11)
        )
    entries.extend(additions)
    trailer.ino = next_ino + len(additions)
    entries.append(trailer)

    cpio = b"".join(pack_newc(entry) for entry in entries)
    cpio += b"\0" * (align(len(cpio), 512) - len(cpio))
    OUT.mkdir(parents=True, exist_ok=True)
    cpio_path = OUT / "platform-taiko-linux-v5.cpio"
    lz4_path = OUT / "platform-taiko-linux-v5.lz4"
    cpio_path.write_bytes(cpio)
    subprocess.run(
        [str(MAGISKBOOT), "compress=lz4_legacy", str(cpio_path), str(lz4_path)],
        check=True,
    )
    verify_path = OUT / "platform-taiko-linux-v5.verify.cpio"
    subprocess.run([str(MAGISKBOOT), "decompress", str(lz4_path), str(verify_path)], check=True)
    if verify_path.read_bytes() != cpio:
        raise ValueError("LZ4 legacy round trip failed")
    verify_path.unlink()

    parsed = {entry.name: entry for entry in parse_newc(cpio)}
    if parsed["p"].data != LOADER or parsed["taiko/modules.ufs-order"].data != order_blob:
        raise ValueError("integrated loader verification failed")
    if not parsed["taiko/busybox"].data.startswith(b"\x7fELF"):
        raise ValueError("integrated BusyBox is not ELF")

    report = {
        "source_cpio_sha256": sha(source),
        "cpio_size": len(cpio),
        "cpio_sha256": sha(cpio),
        "lz4_size": lz4_path.stat().st_size,
        "lz4_sha256": sha(lz4_path.read_bytes()),
        "loader_sha256": sha(LOADER),
        "busybox_sha256": sha(BUSYBOX.read_bytes()),
        "observed_modules": len(order),
        "watchdog_skipped": "mtk_wdt.ko",
        "last_module": order[-1][0],
        "removed_platform_file": "system/bin/adbd",
        "removed_platform_file_sha256": sha(adbd[0].data),
        "loader_integrated": True,
    }
    (OUT / "build.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
