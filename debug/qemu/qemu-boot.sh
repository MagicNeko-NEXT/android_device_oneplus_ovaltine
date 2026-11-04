#!/bin/bash
# QEMU bring-up tests for an ovaltine build. No phone involved; see README.md.
#   qemu-boot.sh prepare            unpack images, build the scratch disk
#   qemu-boot.sh kernel             kernel only, tiny init, power off
#   qemu-boot.sh modules            load every module in dependency order
#   qemu-boot.sh android [seconds] [enforcing]  real boot chain (default 600s, permissive)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
top="${ANDROID_BUILD_TOP:-$(cd "$here/../../../../.." && pwd)}"
out="${OVALTINE_OUT:-$top/out/target/product/ovaltine}"
bin="$top/out/host/linux-x86/bin"
work="${QEMU_WORK:-$top/out/qemu-ovaltine}"
qemu="${QEMU_BIN:-$top/prebuilts/android-emulator/trusty-x86_64/bin/qemu-system-aarch64}"
smp="${QEMU_SMP:-8}"
mem="${QEMU_MEM:-12288}"
pcie=4010000000.pcie
machine=(-M virt,gic-version=3 -accel tcg,thread=multi -cpu max,pauth-impdef=on -smp "$smp" -m "$mem"
         -nodefaults -display none -no-reboot)
console="console=ttyAMA0 earlycon=pl011,0x9000000 ignore_loglevel panic=-1 printk.devkmsg=on"

prepare() {
    rm -rf "$work"; mkdir -p "$work/boot" "$work/vb" "$work/rd_vendor"
    cd "$work"
    "$bin/unpack_bootimg" --boot_img "$out/boot.img" --out boot >/dev/null
    "$bin/unpack_bootimg" --boot_img "$out/vendor_boot.img" --out vb >/dev/null
    (cd rd_vendor && lz4 -dc ../vb/vendor_ramdisk00 2>/dev/null | cpio -idm --quiet --no-absolute-filenames)

    # Small init for the kernel and module tests.
    aarch64-linux-gnu-gcc -static -O1 -w -o init "$here/modtest_init.c"
    mkdir rootA rootM; cp init rootA/; cp init rootM/
    python3 -I "$here/mkorder.py" . rootM "$out/vendor_dlkm/lib/modules"
    (cd rootA && find . | cpio -o -H newc --quiet > ../initA.cpio)
    (cd rootM && find . | cpio -o -H newc --quiet > ../initM.cpio)

    # Device tree: QEMU's own, adjusted to match the phone's paths.
    "$qemu" "${machine[@]/#virt,gic-version=3/virt,gic-version=3,dumpdtb=virt.dtb}" -device qemu-xhci,id=x 2>/dev/null || true
    "$bin/dtc" -I dtb -O dts -q virt.dtb -o virt.dts
    python3 -I "$here/patch_dt.py" virt.dts virt-android.dts
    "$bin/dtc" -I dts -O dtb -q virt-android.dts -o virt-android.dtb

    # Disk: real GPT names, super with the phone's geometry, blank userdata.
    local args=() p sz
    for p in system system_ext product vendor odm vendor_dlkm; do
        sz=$(stat -c%s "$out/$p.img")
        args+=(--partition "${p}_a:readonly:$sz:qti_dynamic_partitions_a" --image "${p}_a=$out/$p.img"
               --partition "${p}_b:readonly:0:qti_dynamic_partitions_b")
    done
    "$bin/lpmake" --metadata-size 65536 --super-name super --metadata-slots 3 --device super:11274289152 \
        --group qti_dynamic_partitions_a:11270094848 --group qti_dynamic_partitions_b:11270094848 \
        "${args[@]}" --output super.raw 2>&1 | grep -E 'error|Error|fail' || true
    truncate -s 256M metadata.raw
    "$bin/mke2fs" -q -t ext4 -b 4096 metadata.raw
    python3 -I "$here/mkdisk.py" "$out"
    rm -f super.raw metadata.raw
    echo "prepared: $work"
}

need() { [ -f "$work/disk.raw" ] || { echo "run: $0 prepare" >&2; exit 2; }; cd "$work"; }

case "${1:-}" in
prepare) prepare ;;
kernel)
    need
    timeout --foreground 300 "$qemu" "${machine[@]}" -serial stdio -kernel boot/kernel -initrd initA.cpio \
        -append "$console" </dev/null | tee kernel.log
    grep -q 'QT SMOKE_OK' kernel.log && echo "PASS: kernel reached userspace" || { echo "FAIL"; exit 1; }
    ;;
modules)
    need
    timeout --foreground 1500 "$qemu" "${machine[@]}" -serial stdio -kernel boot/kernel -initrd initM.cpio \
        -append "$console qt=mods ${2:+skip=$2}" </dev/null > modules.log 2>&1 || true
    grep -a 'QT MODS_DONE' modules.log || echo "no summary: the last 'QT LOAD' line is the suspect"
    grep -a 'QT RES .*err=' modules.log || true
    grep -aE 'Internal error|Kernel panic|Unable to handle' modules.log || true
    grep -aq 'QT SETTLE_OK' modules.log && echo "settled: $work/modules.log"
    ;;
android)
    need
    secs="${2:-600}"; selinux="${3:-permissive}"
    python3 -I "$here/bootcfg.py" bootconfig vb/bootconfig \
        androidboot.slot_suffix=_a androidboot.boot_devices=soc/$pcie androidboot.bootdevice=$pcie \
        androidboot.force_normal_boot=1 androidboot.verifiedbootstate=orange androidboot.veritymode=enforcing \
        androidboot.vbmeta.device_state=unlocked androidboot.selinux="$selinux" androidboot.console=ttyAMA0 \
        androidboot.serialno=QEMU0001
    cat vb/vendor_ramdisk00 boot/ramdisk bootconfig > initrd.img
    rc=0
    timeout --foreground "$secs" "$qemu" "${machine[@]}" -serial stdio \
        -device qemu-xhci,id=x -drive if=none,id=d0,format=raw,file=disk.raw,cache=unsafe \
        -device usb-storage,bus=x.0,drive=d0 -dtb virt-android.dtb -kernel boot/kernel -initrd initrd.img \
        -append "$console bootconfig" </dev/null > android.log 2>&1 || rc=$?
    echo "exit=$rc log=$work/android.log"
    ;;
*) sed -n 2,6p "$0"; exit 2 ;;
esac
