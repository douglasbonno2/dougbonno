#!/usr/bin/env python3
"""Build Taiko native Ubuntu loader V14 using static BusyBox modprobe."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

sys.path.insert(0, "/workspace/tools")
from build_taiko_platform_v5 import Entry, align, pack_newc, parse_newc

ROOT = Path("/workspace")
# Public stock PLATFORM ramdisk from kodeaqua/android_device_xiaomi_taiko_wip.
# The build accepts an explicit local path to keep the published recipe auditable.
SOURCE = Path(os.environ.get(
    "TAIKO_PUBLIC_CPIO",
    "/tmp/taiko-public-ramdisk/vendor_ramdisk.cpio",
))
SOURCE_PUBLIC_URL = (
    "https://github.com/kodeaqua/android_device_xiaomi_taiko_wip/"
    "blob/lineage-23.0/prebuilt/vendor_ramdisk.cpio.lz4"
)
SOURCE_LZ4_SHA256 = "2b2c6fcec6a797416ae62c118536f0e444c5ea1a6c71b496ca42bb32c0f36332"
SOURCE_CPIO_SHA256 = "60d0ab453782fa2e10275dedecb5b381a5fccaa8955dc06c6946095ad36cef09"
BUSYBOX = ROOT / "scratch/tablet-rom/native-linux/magisk31-arm64-v8a-libbusybox.so"
MAGISKBOOT = ROOT / "scratch/tablet-rom/native-linux/magisk31-x86_64-libmagiskboot.so"
OUT = ROOT / "outputs/Taiko-Ubuntu-24.04/loader-v14"
KERNEL_RELEASE = "6.12.30-android16-5-g6e872b4863d6-ab13847919-4k"
ORIGINAL_LZ4_SIZE = 27_924_597
TARGET_LZ4_SIZE = ORIGINAL_LZ4_SIZE + 700

LOADER = br'''#!/taiko/busybox sh
B=/taiko/busybox
L(){ echo "<6>TAIKO_LINUX_V14:$*" >/dev/kmsg 2>/dev/null; }
P(){ L "PARADO:$*"; $B sync; while :; do $B sleep 60; done; }
$B mount -t proc proc /proc 2>/dev/null || :
$B mount -t sysfs sysfs /sys 2>/dev/null || :
$B mount -t devtmpfs devtmpfs /dev 2>/dev/null || :
$B mkdir -p /newroot /dev/pts
$B mount -t devpts devpts /dev/pts 2>/dev/null || :
[ -e /dev/kmsg ] || $B mknod /dev/kmsg c 1 11
L PID1-busybox-modprobe
L antes-modprobe
rc=0
$B modprobe -a $($B cat /lib/modules/modules.load) 2>/dev/kmsg || rc=$?
L "depois-modprobe:rc=$rc"
i=0
while [ $i -lt 30 ] && [ ! -e /sys/class/block/sdc73/dev ]; do
  i=$((i+1)); L "aguarda-sdc73:$i"; $B sleep 1
done
[ -e /sys/class/block/sdc73/dev ] || P sdc73-ausente
IFS=: read MAJ MIN </sys/class/block/sdc73/dev
[ -b /dev/sdc73 ] || $B mknod /dev/sdc73 b "$MAJ" "$MIN" || P mknod-sdc73
L "sdc73=$MAJ:$MIN"
$B mount -t ext4 -o rw,noatime /dev/sdc73 /newroot || P mount-ext4
[ -x /newroot/sbin/init ] || P systemd-ausente
$B mkdir -p /newroot/var/log /newroot/proc /newroot/sys /newroot/dev /newroot/run/initramfs
echo ufs-mounted-v14 >/newroot/var/log/taiko-loader-stage
$B sync
L Ubuntu-montado
$B mount --move /proc /newroot/proc || P move-proc
$B mount --move /sys /newroot/sys || P move-sys
$B mount --move /dev /newroot/dev || P move-dev
cd /newroot || P cd-newroot
$B pivot_root . run/initramfs || P pivot-root
echo systemd-v14 >/var/log/taiko-loader-stage
sync
echo '<6>TAIKO_LINUX_V14:systemd' >/dev/kmsg
exec /sbin/init
P exec-systemd
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def deterministic_pad(size: int) -> bytes:
    out = bytearray()
    counter = 0
    while len(out) < size:
        out += hashlib.sha256(b"TAIKO-V14-PAD" + counter.to_bytes(8, "little")).digest()
        counter += 1
    return bytes(out[:size])


def build_cpio(pad_size: int):
    entries = parse_newc(SOURCE.read_bytes())
    names = {entry.name for entry in entries}
    required = {
        "lib/modules/modules.dep",
        "lib/modules/modules.load",
        "lib/modules/modules.alias",
        "lib/modules/modules.softdep",
    }
    if not required.issubset(names):
        raise ValueError(f"missing module metadata: {sorted(required - names)}")

    adbd = [entry for entry in entries if entry.name == "system/bin/adbd"]
    if len(adbd) != 1:
        raise ValueError("adbd not found")
    entries = [entry for entry in entries if entry.name != "system/bin/adbd"]
    trailer = entries.pop()
    inode = max(entry.ino for entry in entries) + 1

    additions = [
        Entry("taiko", inode, 0o040755, 0, 0, 1, 0, b""),
        Entry("taiko/busybox", inode + 1, 0o100750, 0, 0, 1, 0, BUSYBOX.read_bytes()),
        Entry("taiko/pad", inode + 2, 0o100600, 0, 0, 1, 0, deterministic_pad(pad_size)),
        Entry("p", inode + 3, 0o100750, 0, 0, 1, 0, LOADER),
        # BusyBox modprobe searches /lib/modules/$(uname -r).  The captured
        # stock ramdisk stores its exact modules and metadata one level up.
        Entry(f"lib/modules/{KERNEL_RELEASE}", inode + 4, 0o120777, 0, 0, 1, 0, b"."),
    ]
    if "dev/kmsg" not in names:
        additions.append(
            Entry("dev/kmsg", inode + 5, 0o020600, 0, 0, 1, 0, b"", rdevmajor=1, rdevminor=11)
        )
    entries.extend(additions)
    trailer.ino = inode + len(additions)
    entries.append(trailer)
    cpio = b"".join(pack_newc(entry) for entry in entries)
    cpio += b"\0" * (align(len(cpio), 512) - len(cpio))
    return cpio, sha(adbd[0].data)


def main():
    if sha(SOURCE.read_bytes()) != SOURCE_CPIO_SHA256:
        raise ValueError("public stock ramdisk hash mismatch")
    OUT.mkdir(parents=True, exist_ok=True)
    pad_size = 73_000
    for attempt in range(6):
        cpio, adbd_hash = build_cpio(pad_size)
        cpio_path = OUT / "platform-taiko-linux-v14.cpio"
        lz4_path = OUT / "platform-taiko-linux-v14.lz4"
        cpio_path.write_bytes(cpio)
        subprocess.run(
            [str(MAGISKBOOT), "compress=lz4_legacy", str(cpio_path), str(lz4_path)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        size = lz4_path.stat().st_size
        delta = TARGET_LZ4_SIZE - size
        print("attempt", attempt + 1, "pad", pad_size, "lz4", size, "target_delta", delta)
        if ORIGINAL_LZ4_SIZE <= size < ORIGINAL_LZ4_SIZE + 1_400:
            break
        pad_size = max(0, pad_size + delta)
    else:
        raise ValueError("unable to fit ramdisk in verified vendor_boot slack")

    verify_path = OUT / "verify.cpio"
    subprocess.run([str(MAGISKBOOT), "decompress", str(lz4_path), str(verify_path)], check=True)
    if verify_path.read_bytes() != cpio:
        raise ValueError("LZ4 round trip failed")
    verify_path.unlink()

    parsed = {entry.name: entry for entry in parse_newc(cpio)}
    link_name = f"lib/modules/{KERNEL_RELEASE}"
    if parsed["p"].data != LOADER:
        raise ValueError("loader mismatch")
    if sha(parsed["taiko/busybox"].data) != sha(BUSYBOX.read_bytes()):
        raise ValueError("busybox mismatch")
    if parsed[link_name].data != b"." or (parsed[link_name].mode & 0o170000) != 0o120000:
        raise ValueError("kernel-release module symlink mismatch")

    module_load = parsed["lib/modules/modules.load"].data.decode().splitlines()
    module_names = {Path(name).name for name in parsed if name.endswith(".ko")}
    missing = sorted({Path(name).name for name in module_load} - module_names)
    if missing:
        raise ValueError(f"modules.load references missing modules: {missing}")

    report = {
        "source_public_url": SOURCE_PUBLIC_URL,
        "source_lz4_sha256": SOURCE_LZ4_SHA256,
        "source_cpio_sha256": sha(SOURCE.read_bytes()),
        "cpio_size": len(cpio),
        "cpio_sha256": sha(cpio),
        "lz4_size": size,
        "lz4_growth": size - ORIGINAL_LZ4_SIZE,
        "lz4_sha256": sha(lz4_path.read_bytes()),
        "loader_sha256": sha(LOADER),
        "busybox_sha256": sha(BUSYBOX.read_bytes()),
        "removed_adbd_sha256": adbd_hash,
        "padding_size": pad_size,
        "kernel_release": KERNEL_RELEASE,
        "module_load_entries": len(module_load),
        "module_load_unique": len(set(module_load)),
        "module_references_missing": missing,
        "strategy": "static BusyBox modprobe -a with public Taiko stock modules.dep/modules.load",
    }
    (OUT / "build.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
