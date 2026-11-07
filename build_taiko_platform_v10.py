#!/usr/bin/env python3
"""Integrate the Taiko Ubuntu V10 loader into the primary platform ramdisk."""
from __future__ import annotations
import hashlib, importlib.util, json, sys, subprocess
from pathlib import Path
ROOT=Path('/workspace')
SOURCE_TOOL=ROOT/'tools/build_taiko_platform_v5.py'
SOURCE_CPIO=ROOT/'analysis/taiko-loader-initrd-full/taiko-loader-initrd.dec'
OUT=ROOT/'outputs/Taiko-Ubuntu-24.04/loader-v10'
spec=importlib.util.spec_from_file_location('native_probe_v10', SOURCE_TOOL)
native=importlib.util.module_from_spec(spec); assert spec.loader
sys.modules[spec.name]=native; spec.loader.exec_module(native)
LOADER=b'''#!/system/bin/sh
T=/system/bin/toybox
L(){ echo "<6>TAIKO_LINUX_V10:$*" >/dev/kmsg 2>/dev/null; }
P(){ L "PANIC $*";echo 3 >/proc/sys/kernel/panic;echo 1 >/proc/sys/kernel/sysrq;echo c >/proc/sysrq-trigger;while :;do :;done; }
$T mount -t proc proc /proc 2>/dev/null||:
$T mount -t sysfs sysfs /sys 2>/dev/null||:
$T mount -t devtmpfs devtmpfs /dev 2>/dev/null||:
$T mkdir -p /newroot /dev/pts
$T mount -t devpts devpts /dev/pts 2>/dev/null||:
L PID1-ordem-android
c=0
while read m;do
 [ -n "$m" ]||continue
 c=$((c+1));L "antes=$c:$m"
 rc=0;$T insmod "/lib/modules/$m" 2>/dev/kmsg||rc=$?
 L "depois=$c:$m:rc=$rc"
 if [ "$m" = phy-mtk-ufs.ko ];then
  i=0;while [ $i -lt 30 ]&&[ ! -e /sys/class/block/sdc73/dev ];do i=$((i+1));$T sleep 0.1;done
  [ -e /sys/class/block/sdc73/dev ]&&break
 fi
 [ $c -ge 132 ]&&break
done </lib/modules/modules.load
L "fim-modulos=$c"
[ -e /sys/class/block/sdc73/dev ]||P sdc73-ausente
IFS=: read A B </sys/class/block/sdc73/dev
[ -b /dev/sdc73 ]||$T mknod /dev/sdc73 b "$A" "$B"||P mknod
L "sdc73=$A:$B"
$T mount -t ext4 -o rw,noatime /dev/sdc73 /newroot||P mount-ext4
[ -x /newroot/sbin/init ]||P systemd-ausente
$T mkdir -p /newroot/var/log /newroot/proc /newroot/sys /newroot/dev /newroot/run/initramfs
echo ufs-mounted-v10 >/newroot/var/log/taiko-loader-stage
$T sync;L Ubuntu-montado
$T mount --move /proc /newroot/proc||P move-proc
$T mount --move /sys /newroot/sys||P move-sys
$T mount --move /dev /newroot/dev||P move-dev
$T mount --bind /newroot /newroot||P bind
cd /newroot||P cd
$T pivot_root . run/initramfs||P pivot
echo systemd-v10 >/var/log/taiko-loader-stage
sync
echo '<6>TAIKO_LINUX_V10:systemd' >/dev/kmsg
exec /sbin/init
'''
def sha(x:bytes)->str:return hashlib.sha256(x).hexdigest()
def main():
 import re
 dmesg=(ROOT/'analysis/taiko-retain-20261107/dmesg.txt').read_text(errors='replace')
 pattern=re.compile(r"init: Loading module /lib/modules/([^ ]+) with args '(.*)'")
 observed=[m.group(1) for m in pattern.finditer(dmesg)]
 if len(observed)!=197 or len(set(observed))!=197: raise ValueError('known-good module trace incomplete')
 if observed[9]!='ufs-mediatek-dbg.ko' or observed[12]!='ufs-mediatek-mod.ko' or observed[130]!='reset-ti-syscon.ko' or observed[131]!='phy-mtk-ufs.ko': raise ValueError('known-good UFS order changed')
 entries=native.parse_newc(SOURCE_CPIO.read_bytes()); names={e.name for e in entries}
 load=[e for e in entries if e.name=='lib/modules/modules.load']
 if len(load)!=1: raise ValueError('modules.load missing')
 load[0].data=(''.join(x+'\n' for x in observed)).encode()
 if 'p' in names: raise ValueError('source already contains /p')
 trailer=entries.pop(); ino=max(e.ino for e in entries)+1
 entries.append(native.Entry('p',ino,0o100750,0,0,1,0,LOADER))
 if 'dev/kmsg' not in names:
  entries.append(native.Entry('dev/kmsg',ino+1,0o020600,0,0,1,0,b'',rdevmajor=1,rdevminor=11));ino+=1
 trailer.ino=ino+1;entries.append(trailer)
 cpio=b''.join(native.pack_newc(e) for e in entries);cpio+=b'\0'*(native.align(len(cpio),512)-len(cpio))

 OUT.mkdir(parents=True,exist_ok=True)
 cpio_path=OUT/'platform-taiko-linux-v10.cpio';lz4_path=OUT/'platform-taiko-linux-v10.lz4';verify=OUT/'verify.cpio'
 cpio_path.write_bytes(cpio)
 subprocess.run([str(native.MAGISKBOOT),'compress=lz4_legacy',str(cpio_path),str(lz4_path)],check=True)
 subprocess.run([str(native.MAGISKBOOT),'decompress',str(lz4_path),str(verify)],check=True)
 if verify.read_bytes()!=cpio:raise ValueError('round trip failed')
 verify.unlink();lz4=lz4_path.read_bytes()
 parsed={e.name:e for e in native.parse_newc(cpio)}
 if parsed['p'].data!=LOADER:raise ValueError('loader mismatch')
 report={'source_cpio_sha256':sha(SOURCE_CPIO.read_bytes()),'cpio_size':len(cpio),'cpio_sha256':sha(cpio),'lz4_size':len(lz4),'lz4_sha256':sha(lz4),'loader_sha256':sha(LOADER),'loader_integrated':True,'module_cap':132,'module_order':'known-good Android dmesg','module_order_sha256':sha(load[0].data)}
 (OUT/'build.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
