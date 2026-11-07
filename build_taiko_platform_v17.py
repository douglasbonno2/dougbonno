#!/usr/bin/env python3
"""Build native Taiko Ubuntu PLATFORM ramdisk from the exact stock HyperOS ramdisk."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

sys.path.insert(0, "/workspace/tools")
from build_taiko_platform_v5 import Entry, align, pack_newc, parse_newc

ROOT = Path("/workspace")
SOURCE = Path("/tmp/taiko-stock-fragments/0-1-platform.cpio")
SOURCE_SHA256 = "4c6d19020b07aab4e7d17361d79847d53ef710990fba55f92a3b2b8c2463aa5e"
BUSYBOX = ROOT / "scratch/tablet-rom/native-linux/magisk31-arm64-v8a-libbusybox.so"
MAGISKBOOT = ROOT / "scratch/tablet-rom/native-linux/magisk31-x86_64-libmagiskboot.so"
OUT = ROOT / "outputs/Taiko-Ubuntu-24.04/loader-v17"
KERNEL_RELEASE = "6.12.30-android16-5-g6e872b4863d6-ab13847919-4k"

LOADER = br'''#!/taiko/busybox sh
B=/taiko/busybox
M=/system/bin/modprobe
L(){ echo "<6>TAIKO_LINUX_V17:$*" >/dev/kmsg 2>/dev/null; }
P(){ L "PANIC:$*"; $B sync; echo 0 >/proc/sys/kernel/panic; echo 1 >/proc/sys/kernel/sysrq; echo c >/proc/sysrq-trigger; while :; do :; done; }
$B mount -t proc proc /proc 2>/dev/null || :
$B mount -t sysfs sysfs /sys 2>/dev/null || :
$B mount -t devtmpfs devtmpfs /dev 2>/dev/null || :
$B mkdir -p /newroot /dev/pts
$B mount -t devpts devpts /dev/pts 2>/dev/null || :
[ -e /dev/null ] || $B mknod /dev/null c 1 3
[ -e /dev/zero ] || $B mknod /dev/zero c 1 5
[ -e /dev/random ] || $B mknod /dev/random c 1 8
[ -e /dev/urandom ] || $B mknod /dev/urandom c 1 9
[ -e /dev/kmsg ] || $B mknod /dev/kmsg c 1 11
L PID1-toolbox-modprobe
L antes-modprobe
rc=0
$M -a -d /lib/modules $($B cat /lib/modules/modules.load) 2>/dev/kmsg || rc=$?
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
echo ufs-mounted-v17 >/newroot/var/log/taiko-loader-stage
$B sync
L Ubuntu-montado
$B mount --move /proc /newroot/proc || P move-proc
$B mount --move /sys /newroot/sys || P move-sys
$B mount --move /dev /newroot/dev || P move-dev
cd /newroot || P cd-newroot
$B pivot_root . run/initramfs || P pivot-root
echo systemd-v17 >/var/log/taiko-loader-stage
sync
echo '<6>TAIKO_LINUX_V17:systemd' >/dev/kmsg
exec /sbin/init
P exec-systemd
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main():
    source = SOURCE.read_bytes()
    if sha(source) != SOURCE_SHA256:
        raise ValueError("stock HyperOS PLATFORM ramdisk hash mismatch")
    entries = parse_newc(source)
    names = {entry.name for entry in entries}
    required = {
        "init",
        "system/bin/init",
        "lib/modules/modules.dep",
        "lib/modules/modules.load",
        "lib/modules/modules.alias",
        "lib/modules/modules.softdep",
    }
    if not required.issubset(names):
        raise ValueError(f"missing stock entries: {sorted(required - names)}")

    original_init = next(entry for entry in entries if entry.name == "init")
    entries = [entry for entry in entries if entry.name != "init"]
    trailer = entries.pop()
    inode = max(entry.ino for entry in entries) + 1
    additions = [
        Entry("taiko", inode, 0o040755, 0, 0, 1, 0, b""),
        Entry("taiko/busybox", inode + 1, 0o100750, 0, 0, 1, 0, BUSYBOX.read_bytes()),
        Entry("taiko/android-first-stage-init", inode + 2, 0o100750, 0, 0, 1, 0, original_init.data),
        Entry("init", inode + 3, 0o100750, 0, 0, 1, 0, LOADER),
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

    OUT.mkdir(parents=True, exist_ok=True)
    cpio_path = OUT / "platform-taiko-linux-v17.cpio"
    lz4_path = OUT / "platform-taiko-linux-v17.lz4"
    verify_path = OUT / "verify.cpio"
    cpio_path.write_bytes(cpio)
    subprocess.run(
        [str(MAGISKBOOT), "compress=lz4_legacy", str(cpio_path), str(lz4_path)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    subprocess.run([str(MAGISKBOOT), "decompress", str(lz4_path), str(verify_path)], check=True)
    if verify_path.read_bytes() != cpio:
        raise ValueError("LZ4 round trip failed")
    verify_path.unlink()

    parsed = {entry.name: entry for entry in parse_newc(cpio)}
    link_name = f"lib/modules/{KERNEL_RELEASE}"
    if parsed["init"].data != LOADER or (parsed["init"].mode & 0o170000) != 0o100000:
        raise ValueError("normal-boot /init mismatch")
    if parsed["taiko/android-first-stage-init"].data != original_init.data:
        raise ValueError("stock first-stage init backup mismatch")
    if parsed[link_name].data != b"." or (parsed[link_name].mode & 0o170000) != 0o120000:
        raise ValueError("module directory symlink mismatch")

    module_load = parsed["lib/modules/modules.load"].data.decode().splitlines()
    module_names = {Path(name).name for name in parsed if name.endswith(".ko")}
    missing = sorted({Path(name).name for name in module_load} - module_names)
    if missing:
        raise ValueError(f"modules.load references missing modules: {missing}")

    report = {
        "source_stock_cpio_sha256": SOURCE_SHA256,
        "stock_init_sha256": sha(original_init.data),
        "stock_init_size": len(original_init.data),
        "cpio_size": len(cpio),
        "cpio_sha256": sha(cpio),
        "lz4_size": lz4_path.stat().st_size,
        "lz4_sha256": sha(lz4_path.read_bytes()),
        "loader_sha256": sha(LOADER),
        "busybox_sha256": sha(BUSYBOX.read_bytes()),
        "kernel_release": KERNEL_RELEASE,
        "module_load_entries": len(module_load),
        "module_load_unique": len(set(module_load)),
        "module_references_missing": missing,
        "strategy": "stock boot unchanged; HyperOS toolbox modprobe; preserve stock recovery fragment",
    }
    (OUT / "build.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
