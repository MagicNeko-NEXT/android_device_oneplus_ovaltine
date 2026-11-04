# QEMU bring-up tests

Runs an ovaltine build's own kernel, ramdisks and partition images under QEMU's
`virt` machine. No phone is involved and the build's images aren't modified.
Output goes to `out/qemu-ovaltine/`.

Needs a finished `custom_ovaltine` build, `lz4`, `cpio`, `sgdisk` and
`aarch64-linux-gnu-gcc`. QEMU comes from `prebuilts/android-emulator`.

    ./qemu-boot.sh prepare                      # unpack images, build scratch disk
    ./qemu-boot.sh kernel                       # kernel boots to userspace
    ./qemu-boot.sh modules [a.ko,b.ko]          # load all modules, optional skip list
    ./qemu-boot.sh android [seconds] [enforcing]  # real boot chain, log in android.log

`android` uses the real boot and vendor ramdisks, bootconfig, GPT partition names and
`super` geometry. It covers module loading, first-stage mount, AVB, SELinux policy
load, init.rc parsing and early services.

## What this can't test

QEMU has none of the phone's hardware: no bootloader or firmware, UFS, display, GPU,
modem, TEE or real device tree. So:

- Passing doesn't prove the phone boots.
- Failures from missing hardware (qseecomd, keymint, WLAN, ...) aren't ROM bugs.
- Test-only differences: USB disk instead of UFS, QEMU's device tree, permissive
  SELinux by default.
