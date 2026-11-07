#!/usr/bin/env python3
"""Build Taiko native loader V13 with static BusyBox and size-stable ramdisk."""
from pathlib import Path
import hashlib,json,subprocess,sys
sys.path.insert(0,'/workspace/tools')
from build_taiko_platform_v5 import Entry,parse_newc,pack_newc,align
ROOT=Path('/workspace')
SOURCE=ROOT/'analysis/taiko-loader-initrd-full/taiko-loader-initrd.dec'
BUSYBOX=ROOT/'scratch/tablet-rom/native-linux/magisk31-arm64-v8a-libbusybox.so'
MB=ROOT/'scratch/tablet-rom/native-linux/magisk31-x86_64-libmagiskboot.so'
OUT=ROOT/'outputs/Taiko-Ubuntu-24.04/loader-v13'
ORIGINAL_LZ4_SIZE=27924597
TARGET=ORIGINAL_LZ4_SIZE+700
MODULES=['rpmb.ko','mrdump.ko','blocktag.ko','irq-dbg.ko','aee_aed.ko','ufs-mediatek-dbg.ko','miev.ko','ufs-mediatek-mod.ko','reset-ti-syscon.ko','phy-mtk-ufs.ko']
LOADER=b'''#!/taiko/busybox sh
B=/taiko/busybox
L(){ echo "<6>TAIKO_LINUX_V13:$*" >/dev/kmsg 2>/dev/null; }
P(){ L "PANIC $*";$B sync;echo 3 >/proc/sys/kernel/panic;echo 1 >/proc/sys/kernel/sysrq;echo c >/proc/sysrq-trigger;while :;do :;done; }
$B mount -t proc proc /proc 2>/dev/null||:
$B mount -t sysfs sysfs /sys 2>/dev/null||:
$B mount -t devtmpfs devtmpfs /dev 2>/dev/null||:
$B mkdir -p /newroot /dev/pts
$B mount -t devpts devpts /dev/pts 2>/dev/null||:
[ -e /dev/kmsg ]||$B mknod /dev/kmsg c 1 11
L PID1-estatico-minimo
c=0
for m in rpmb.ko mrdump.ko blocktag.ko irq-dbg.ko aee_aed.ko ufs-mediatek-dbg.ko miev.ko ufs-mediatek-mod.ko reset-ti-syscon.ko phy-mtk-ufs.ko;do
 c=$((c+1));L "antes=$c:$m"
 rc=0;$B insmod "/lib/modules/$m" 2>/dev/kmsg||rc=$?
 L "depois=$c:$m:rc=$rc"
done
L fim-modulos-minimos
i=0
while [ $i -lt 10 ]&&[ ! -e /sys/class/block/sdc73/dev ];do i=$((i+1));$B sleep 1;done
[ -e /sys/class/block/sdc73/dev ]||P sdc73-ausente
IFS=: read A BMIN </sys/class/block/sdc73/dev
[ -b /dev/sdc73 ]||$B mknod /dev/sdc73 b "$A" "$BMIN"||P mknod
L "sdc73=$A:$BMIN"
$B mount -t ext4 -o rw,noatime /dev/sdc73 /newroot||P mount-ext4
[ -x /newroot/sbin/init ]||P systemd-ausente
$B mkdir -p /newroot/var/log /newroot/proc /newroot/sys /newroot/dev /newroot/run/initramfs
echo ufs-mounted-v13 >/newroot/var/log/taiko-loader-stage
$B sync;L Ubuntu-montado
$B mount --move /proc /newroot/proc||P move-proc
$B mount --move /sys /newroot/sys||P move-sys
$B mount --move /dev /newroot/dev||P move-dev
$B mount --bind /newroot /newroot||P bind
cd /newroot||P cd
$B pivot_root . run/initramfs||P pivot
echo systemd-v13 >/var/log/taiko-loader-stage
sync
echo '<6>TAIKO_LINUX_V13:systemd' >/dev/kmsg
exec /sbin/init
'''
def sha(b):return hashlib.sha256(b).hexdigest()
def random_pad(n):
 out=bytearray();i=0
 while len(out)<n:
  out+=hashlib.sha256(b'TAIKO-V13-PAD'+i.to_bytes(8,'little')).digest();i+=1
 return bytes(out[:n])
def build(pad_size):
 entries=parse_newc(SOURCE.read_bytes());names={e.name for e in entries}
 adbd=[e for e in entries if e.name=='system/bin/adbd']
 if len(adbd)!=1:raise ValueError('adbd not found')
 entries=[e for e in entries if e.name!='system/bin/adbd'];trailer=entries.pop();ino=max(e.ino for e in entries)+1
 additions=[Entry('taiko',ino,0o040755,0,0,1,0,b''),Entry('taiko/busybox',ino+1,0o100750,0,0,1,0,BUSYBOX.read_bytes()),Entry('taiko/pad',ino+2,0o100600,0,0,1,0,random_pad(pad_size)),Entry('p',ino+3,0o100750,0,0,1,0,LOADER)]
 if 'dev/kmsg' not in names:additions.append(Entry('dev/kmsg',ino+4,0o020600,0,0,1,0,b'',rdevmajor=1,rdevminor=11))
 entries.extend(additions);trailer.ino=ino+len(additions);entries.append(trailer)
 cpio=b''.join(pack_newc(e) for e in entries);cpio+=b'\0'*(align(len(cpio),512)-len(cpio))
 return cpio,sha(adbd[0].data)
def main():
 OUT.mkdir(parents=True,exist_ok=True);pad=73000
 for attempt in range(5):
  cpio,adbd_hash=build(pad);cp=OUT/'platform-taiko-linux-v13.cpio';lz=OUT/'platform-taiko-linux-v13.lz4';cp.write_bytes(cpio)
  subprocess.run([str(MB),'compress=lz4_legacy',str(cp),str(lz)],check=True,stdout=subprocess.DEVNULL)
  size=lz.stat().st_size;delta=TARGET-size
  print('attempt',attempt+1,'pad',pad,'lz4',size,'target_delta',delta)
  if ORIGINAL_LZ4_SIZE <= size < ORIGINAL_LZ4_SIZE+1400:break
  pad=max(0,pad+delta)
 else:raise ValueError('unable to size ramdisk')
 verify=OUT/'verify.cpio';subprocess.run([str(MB),'decompress',str(lz),str(verify)],check=True)
 if verify.read_bytes()!=cpio:raise ValueError('round trip failed')
 verify.unlink();parsed={e.name:e for e in parse_newc(cpio)}
 if parsed['p'].data!=LOADER or sha(parsed['taiko/busybox'].data)!=sha(BUSYBOX.read_bytes()):raise ValueError('payload mismatch')
 report={'source_cpio_sha256':sha(SOURCE.read_bytes()),'cpio_size':len(cpio),'cpio_sha256':sha(cpio),'lz4_size':size,'lz4_growth':size-ORIGINAL_LZ4_SIZE,'lz4_sha256':sha(lz.read_bytes()),'loader_sha256':sha(LOADER),'busybox_sha256':sha(BUSYBOX.read_bytes()),'removed_adbd_sha256':adbd_hash,'padding_size':pad,'modules_minimal':MODULES}
 (OUT/'build.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
