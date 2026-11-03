# Vulkan ICD switching (without changing the system framework)

Goal: switch the Vulkan driver (OEM `vulkan.adreno.so` / Mesa `vulkan.freedreno.so`) per app at runtime,
**without modifying `frameworks/native`**, so nothing is lost when changing ROMs or rebuilding the framework.

## Why the old approach had to change the framework

`LoadDriver()` in `frameworks/native/vulkan/libvulkan/driver.cpp` has only one path:

```cpp
std::string lib_name = android::base::GetProperty("ro.hardware.vulkan", "");
lib_name = "vulkan." + lib_name + ".so";          // the only entry point
so = android_load_sphal_library(lib_name.c_str(), LIB_DL_FLAGS);
```

`ro.hardware.vulkan` is a read-only `ro.*` property → fixed at build time, not changeable at runtime. So the old approach had to insert
per-app lookup logic into `driver.cpp` (`perapp-vulkan-driver.patch`), which is a system framework patch:
every framework update or ROM change means maintaining the patch again.

## New approach: put the switch in the HAL layer

The loader's contract has only three steps (`frameworks/native/vulkan/libvulkan/driver.cpp`):

1. Open `vulkan.<ro.hardware.vulkan>.so`;
2. `dlsym(so, "HMI")` to get `hw_module_t`, and check `id == "vulkan"`;
3. Call `module->common.methods->open(module, "vk0", &device)`, then use only the three function pointers in `hwvulkan_device_t`
   (`EnumerateInstanceExtensionProperties` / `CreateInstance` / `GetInstanceProcAddr`).

So fix `ro.hardware.vulkan` to `switcher`, and let `vulkan.switcher.so` be that HAL module:

```
libvulkan (stock)
   └─ dlopen vulkan.switcher.so        ← ro.hardware.vulkan=switcher (set once at build time, never changed)
        ├─ read /data/misc/vulkan/per_app.conf (writable, takes priority)
        ├─ read /vendor/etc/vulkan/per_app.conf (image default)
        └─ dlopen vulkan.adreno.so / vulkan.freedreno.so, and hand over its hwvulkan_device_t unchanged
```

`libvulkan` is untouched, both ICDs stay in `/vendor/lib64/hw/`, and switching = changing one config line + restarting that process.

## File list

New in `device/oneplus/ovaltine/vulkan-switcher/`:

| File | Purpose |
|---|---|
| `vulkan_switcher.cpp` | HAL module implementation: selects the ICD, loads it, forwards the device struct |
| `Android.bp` | `cc_library_shared`, outputs `/vendor/lib64/hw/vulkan.switcher.so` |
| `per_app.conf.turnip` | Image default config (`*=freedreno`, Turnip first) |
| `per_app.conf.oem` | Image default config (`*=adreno`, OEM first) |
| `apply-integration.py` | Applies all the changes below to the tree in one go (idempotent) |

Device tree changes:

| File | Change |
|---|---|
| `device/oneplus/ovaltine/device.mk` | Installs `vulkan_switcher`; `ro.hardware.vulkan=switcher`; `GPU_DRIVER_TURNIP` only decides the image default config |
| `device/oneplus/sm8450-common/vendor.prop` | Removes the duplicate `ro.hardware.vulkan=adreno` (a property can only be assigned once) |
| `device/oneplus/sm8450-common/sepolicy/file_contexts` | Labels `vulkan.switcher.so` `same_process_hal_file`; labels `/vendor/etc/vulkan` `vulkan_perapp_conf_file` |
| `device/oneplus/sm8450-common/sepolicy/vulkan_perapp.te` | Adds `allow su` write access (to edit the mapping directly with adb root) |
| `device/oneplus/sm8450-common/init/init.qcom.rc` | `mkdir /data/misc/vulkan 0770 system system` |
| `device/oneplus/sm8450-common/common.mk` | 4 boolean `soong_config_set` → `soong_config_set_bool` (hardware/oplus bp files use boolean select keys, and a type mismatch blocks soong) |

## Config syntax

```
# /data/misc/vulkan/per_app.conf  or  /vendor/etc/vulkan/per_app.conf
<package>=<subname>
*= <subname>
```

* An exact package name takes priority over `*`; `/data` takes priority over `/vendor/etc`.
* `subname` may only contain `[a-z0-9_-]` (prevents path injection); unknown or mistyped values are ignored.
* Candidate order: config → `*` in `/vendor/etc` → hardcoded `adreno` → `freedreno`.
  If an ICD fails to open it moves to the next one, and at worst falls back to the stub HAL, so a process is never left without Vulkan.

Common operations (`adb root`):

```bash
# Switch everything to Turnip
adb shell 'echo "*=freedreno" > /data/misc/vulkan/per_app.conf'
# Switch one app back to the OEM driver
adb shell 'echo "com.tungsten.fcl=adreno" >> /data/misc/vulkan/per_app.conf'
# Apply: restart the process
adb shell am force-stop com.tungsten.fcl
```

Verify:

```bash
adb logcat -s vkswitch                       # should show "pkg=<package> configured=... -> freedreno"
adb shell dumpsys gpu | grep -i -A3 vulkan   # shows the ICD the current process actually uses
```

## Verification status

* The code compiles against the tree's headers (`clang-r563880c`, `--target=aarch64-linux-android34`,
  `-Wall -Wextra`; only a `missing field 'dso' initializer` note remains, which is static zero-initialization, same as `nulldrv`).
* The linked output exports `HMI` with **default visibility (`D`)**, the symbol the loader's `dlsym(so, "HMI")` needs.
* On-device behavior (which ICD loads, per-app switching) is not yet verified; the full build is currently blocked by the environment problem below.

## Risks and rollback

* Risk: if `vulkan.switcher.so` itself crashes, `libvulkan` gets no HAL (falls back to the stub, meaning no Vulkan).
  Mitigation: it only does `dlopen` + forwarding, and doesn't touch graphics state; it returns failure only if both ICDs fail.
* Risk: if SELinux denies reading the config file, it only falls back to the image default and doesn't crash.
* Rollback: change `ro.hardware.vulkan` back to `freedreno` or `adreno` and rebuild to return to the old "single driver at build time" behavior;
  leaving the shim and config files in place is harmless.

## Current blocker (unrelated to this change)

`m vulkan_switcher` is stuck in soong's full-tree parse:

```
error: vendor/lineage/build/soong/Android.bp:21:1: module "generated_kernel_includes":
       source path kernel/oneplus/sm8450/include/soc/oplus/... does not exist
```

The headers under `kernel/oneplus/sm8450/include/soc/oplus/` are symlinks pointing to
`kernel/oneplus/gki-modules/oplus/kernel/...`, and that directory doesn't exist: when restoring from the 9repo bundle,
`kernel_oneplus_gki-modules.bundle` was a shallow bundle (`fatal: remote did not send all necessary objects`)
and couldn't be cloned. Once that repo is restored, `m vulkan_switcher` / the full build can continue.
