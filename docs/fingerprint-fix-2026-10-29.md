# OnePlus 10T (ovaltine) fingerprint: complete fix record

**Date**: 2026-10-29
**Device**: OnePlus 10T / `ovaltine` / `OP5552L1` / `PGP110`, serial `734ce825`
**Baseline**: aviumui 16.2.2 (lineage-23.2), `lineage_ovaltine-bp4a-userdebug`
**Result**: under-display optical fingerprint enrollment and unlock work

---

## 1. How the symptoms evolved (three stages)

| Stage | Symptom | Root-cause layer |
|---|---|---|
| A | system_server crashes every few seconds after boot, restarting forever | framework fails to parse `getSensorProps` |
| B | System boots, but tapping "Add fingerprint" in Settings immediately shows "Couldn't complete fingerprint setup" | HAL interface version / method set mismatch |
| C | Enrollment page opens and images are captured, but it reports `FP_ERR_FINGERUP_TOO_FAST` and the screen goes dark | panel HBM is never triggered |

The three stages are **chained**: without fixing A you never reach B, and without fixing B you never reach C.

---

## 2. Root-cause chain (7 items, each one necessary)

### 1. The stock HAL was patched by someone to register `oplusfp`

In the vendor firmware, `/odm/bin/hw/vendor.oplus.hardware.biometrics.fingerprint@2.1-service_uff`
originally registers `IFingerprint/default` (the only name the framework accepts). The copy in this tree had been
modified to register `IFingerprint/oplusfp` (562,248 bytes, sha256 `8b54f4af…`), with matching edits to the
VINTF manifest and a comment line in the init rc.

**Fix**: restore the original, unmodified binary.

```
547,633 bytes
sha256 d81177ee5199b677a5a5a2d4a250b5da622c7af1b5e39b857c05b8f4f0260252
```

### 2. The VINTF manifest declares `oplusfp`

In `odm/etc/vintf/manifest/manifest_oplus_fingerprint_aidl_v2.xml`,
`<fqname>` says `IFingerprint/oplusfp`.

**Fix**: change it back to `IFingerprint/default`.

> With 1 and 2 fixed, `service list` shows
> `android.hardware.biometrics.fingerprint.IFingerprint/default`.
> But system_server still crashes, which exposes item 3.

### 3. `SensorProps::writeToParcel` serialization layout mismatch

The HAL was compiled against an old (A14-era) frozen AIDL snapshot, while the framework parses with the current definition.
Three approaches were tried at this layer, and the first two were wrong:

| Approach | Result |
|---|---|
| Copy `*thisptr` by value, then rewrite fields (original LineageOS upstream) | Reads garbage from the old layout (the `componentInfo` vector header); under `-fno-exceptions` it dies in `std::__throw_length_error` → SIGABRT |
| Pass through unchanged | Writes old-layout bytes that the framework reads as the new layout → `FingerprintSensorConfigurations.getSensorPropForInstance` throws `IllegalArgumentException` on the `BiometricServiceRegistry` thread → system_server crash loop |
| **Construct fresh and fill in the new fields** (final solution) | Works |

**Final implementation**:

```cpp
extern "C" binder_status_t
SensorProps::writeToParcel(SensorProps* /*thisptr*/, AParcel* parcel) {
    // Never read *thisptr: it follows the HAL's own old header layout
    SensorProps props;                                  // current layout, default-initialized
    props.commonProps.sensorId = 0;
    props.commonProps.sensorStrength = SensorStrength::STRONG;
    props.commonProps.maxEnrollmentsPerUser = 5;
    props.supportsDetectInteraction = true;
    props.halControlsIllumination = true;
    SensorPropsInit(&props);                            // fill sensorType / locations from system properties

    int32_t start = AParcel_getDataPosition(parcel);
    v2Write(&props, parcel);                            // V2 serializer writes the 7 fields
    AParcel_writeBool(parcel, false);                   // add the nullable field new in the current definition
    int32_t finish = AParcel_getDataPosition(parcel);
    AParcel_setDataPosition(parcel, start);
    AParcel_writeInt32(parcel, finish - start);         // back-fill the block length prefix
    AParcel_setDataPosition(parcel, finish);
    return STATUS_OK;
}
```

> **Why V4 (current) can't be linked**: the HAL is V2, and soong refuses to mix
> `fingerprint-V2-ndk` and `-V4-ndk` in one module graph (`depends on multiple versions of the same aidl_interface`).
> So the only option is V2 types plus manually filling the differences.

### 4. `writeToParcel` return type written as `void`

The generated signature is `binder_status_t SensorProps::writeToParcel(AParcel*) const`,
and the status is returned in **w0**. With `void`, w0 holds garbage and the HAL treats it as failure:

```
W …-service_uff: PruneStatusT: Unknown status_t (1 (Unknown error -1))
                 pruned into STATUS_UNKNOWN_ERROR
```

On the framework side this appears as `java.lang.RuntimeException: Unknown error`.

**This one HAL log line was the turning point of the investigation**: it proved the shim was called and the data was built,
and only the return value was broken.

### 5. Interface version was overridden for `BnSession` only, missing `BnFingerprint`

The framework gets the HAL interface version like this:

```
FingerprintStartUserClient.java:62   final int version = hal.getInterfaceVersion();   // hal is IFingerprint
```

`AidlSession.hasContextMethods()` is just `mHalInterfaceVersion >= 2`.
Version 2 reported → framework calls `enrollWithContext` → this HAL doesn't implement it → `DeadObjectException`.

**Fix**: `getInterfaceVersion` reports 1 for both `BnFingerprint` and `BnSession`, and
`getInterfaceHash` returns `EX_UNSUPPORTED_OPERATION`.

### 6. Wrong ABI in the version override function (SIGSEGV at 0x5)

`ndk::ScopedAStatus` is a **struct return value**, and AAPCS64 passes its address in **x8**.
The first attempt was:

```cpp
extern "C" void f(void* this, int32_t* ver, AStatus** status)   // ← status lands in x2
```

The C compiler makes `status` the third argument (x2), but the caller never puts anything in x2;
it uses x8. So `*status = ...` writes to a garbage address:

```
Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x5
#00 pc 0x55dc  libshims_aidl_fingerprint_v2.oplus.so
     (BnFingerprint::getInterfaceVersion(int*)+36)
```

**Fix**: make it a C++ function returning `ndk::ScopedAStatus` by value,
and use `asm()` to pin the symbol to the mangled name:

```cpp
ndk::ScopedAStatus
opGetFingerprintInterfaceVersion(void* /*thisptr*/, int32_t* version)
        asm("_ZN4aidl7android8hardware10biometrics11fingerprint13BnFingerprint19getInterfaceVersionEPi");

ndk::ScopedAStatus
opGetFingerprintInterfaceVersion(void* /*thisptr*/, int32_t* version) {
    if (version) *version = 1;
    return ndk::ScopedAStatus::ok();
}
```

> You can't simply write `extern "C" ndk::ScopedAStatus …`:
> clang reports `-Wreturn-type-c-linkage` at error level,
> and `-Wno-return-type-c-linkage` doesn't suppress it.

### 7. Panel has no local HBM, and UdfpsExtension is missing

The DTSI is `oplus,ofp-fp-type = <0x08>`, with **no BIT(4) local HBM**:
it can't light up only the fingerprint area, so the whole screen enters HBM and SystemUI's dim layer creates the circular look.

The device tree already tunes the dim layer (`config_udfpsDimmingBrightnessAlphaArray`, 4095 endpoint),
but `hardware/qcom-caf/sm8450/display` **has no `UdfpsExtension` at all**
(only sm8550 / sm8750 do), so the HBM trigger doesn't exist:

```
hbmMode=off
[FP_HAL][OpticalCore]: checkFingerUpTooFast, FP_FINGER_UP FP_ERR_FINGERUP_TOO_FAST
[FP_HAL][IFingerprintCore]: captureImg:323: result:10108
```

The screen is dimmed and brightness never rises → no clear image is captured → enrollment fails.

**Fix**: apply `device/oneplus/sm8450-common/upstream-patches/0001-display-sm8450-udfps-hbm-and-sdmext.patch`
(14 files, `git apply --check` is clean).

---

## 3. Regression caused by fix 7: stuck launcher

After the HBM patch the system doesn't come up. It stays on `FallbackHome`, and `livedisplay` aborts every 5 seconds:

```
F vendor.lineage.livedisplay-impl-sdm: Failed to initialize SDM backend
F DEBUG: Abort message: 'Failed to initialize SDM backend'
PID 4735 → 4782 → 4829 → 4994 (every 5 seconds)
```

**Root cause**: `SDM` allows only one process to hold the DRM master. composer starts first and takes it,
so livedisplay, starting later, is bound to fail. The HBM patch changed `core_impl.cpp`:

```diff
- if ((err != kErrorNone) || !enable_null_display_) {
+ if (err != kErrorNone) {
```

This makes composer's degrade path work (which is correct), but livedisplay takes the same path, gets a
null display, and `CreateCore` still fails, while `SDMController.cpp` has:

```cpp
if (init() != android::OK) {
    LOG(FATAL) << "Failed to initialize SDM backend";   // ← abort
}
```

So init keeps respawning it → crash loop → Launcher never gets the foreground.

**Fix** (`hardware/lineage/interfaces/livedisplay/aidl/sdm/SDMController.cpp`):
livedisplay is only display tuning, an optional component, so an init failure should degrade rather than abort.
The `CONTROLLER_CHECK` macro already checks `hctx_ == 0`, so degrading is safe.

```cpp
if (init() != android::OK) {
    LOG(ERROR) << "Failed to initialize SDM backend, display control unavailable";
    hctx_ = 0;
    return;
}
```

> Note that `hctx_` is a `uint64_t`, not a pointer, so writing `nullptr` fails to compile.

---

## 4. Deployment

### 4.1 Build

```bash
cd /root/aviumui
source build/envsetup.sh
lunch lineage_ovaltine-bp4a-userdebug
m bacon -j32          # about 11-14 minutes (warm cache)
```

### 4.2 Fetch the package (always use a new file name, don't overwrite the old one)

```bash
rsync -a --info=progress2 lupa:/root/aviumui/out/target/product/ovaltine/AviumUI-*.zip \
      ./AviumUI-16.2.2-ovaltine-20261029-hbm-sdmfix.zip
sha256sum AviumUI-16.2.2-ovaltine-20261029-hbm-sdmfix.zip | tee *.sha256
# f3f88598e8f7c8a009a13a0ecdaa6c8456dbcf62962244e1d68dae99b8a27421
```

### 4.3 Flash (sideload only, not fastboot flash)

```bash
adb reboot sideload
adb -s 734ce825 sideload AviumUI-16.2.2-ovaltine-20261029-hbm-sdmfix.zip   # about 4-5 minutes
adb -s 734ce825 reboot
```

> **`fastboot flash vendor_a` has no effect**: super has leftover dm-snapshot COW
> (`vendor_a-cow`), so the write doesn't take effect, and even `delete-logical-partition vendor_a-cow`
> can't clear it. Only a full OTA sideload through update_engine actually lands on disk.

### 4.4 Verify

```bash
adb shell getprop sys.boot_completed          # 1
adb shell getprop ro.build.version.incremental # 1793243681 (matches post-build-incremental in the package)
adb shell service list | grep fingerprint     # IFingerprint/default present
adb logcat -b crash -d | grep -c "SDM backend"   # 0
adb logcat -b crash -d | grep -c "FATAL EXCEPTION"  # 0
adb shell dumpsys biometric | head            # lists ID(1008) modality 8
```

### 4.5 Fast iteration trick (avoids a full sideload)

Modules that don't need a reboot can be hot-swapped, taking about 2 minutes instead of 10:

```bash
# Build only the target module
m libshims_aidl_fingerprint_v2.oplus -j32

# Push to the device and overlay it
adb root
adb push libshims_aidl_fingerprint_v2.oplus.so /data/local/tmp/x.so
adb shell "chcon u:object_r:vendor_file:s0 /data/local/tmp/x.so"
adb shell "mount --bind /data/local/tmp/x.so /odm/lib64/libshims_aidl_fingerprint_v2.oplus.so"
adb shell "setprop ctl.restart fps_hal"
```

**Works for**: the fingerprint HAL shim (`fps_hal` restarts safely).
**Doesn't work for**: `display composer`. It is upstream of SurfaceFlinger,
so after `ctl.stop`, `ctl.start` doesn't bring it back and the whole screen goes black; the bind mount is also lost on reboot.
Display-layer changes require a full flash.

---

## 5. File list

| Repo | Commit | Files |
|---|---|---|
| `hardware/oplus` | `ae0e624` | `fingerprint/shims/SensorPropsShim.cpp`, `fingerprint/shims/Android.bp` |
| `hardware/lineage/interfaces/livedisplay` | `16eabf1` | `aidl/sdm/SDMController.cpp` |
| `hardware/qcom-caf/sm8450/display` | `0489f4cfa5` | 14 files (UdfpsExtension + SDM extension hooks) |
| `device/oneplus/ovaltine` | `303366b` | `device.mk` (disables proxy / HIDL service), `fingerprint/FingerprintProxy.cpp` |
| `vendor/oneplus/ovaltine` | `e02766c` | stock HAL binary, `manifest_oplus_fingerprint_aidl_v2.xml`, init rc |

All pushed to `github.com/MagicNeko-ROM/*`, branch `lineage-23.2`.
`android_hardware_qcom_display` and `android_hardware_lineage_interfaces`
were not previously in that organization and were created for this work.

---

## 6. Debugging lessons

1. **Read the HAL's own logs first**. The `PruneStatusT: Unknown status_t` line is far more useful than the framework's
   exception stack: it shows the error is on the HAL side and concerns the return value.
2. **The tombstone's `#00` frame decides everything**. `BnFingerprint::getInterfaceVersion+36`
   narrows the search to that one function.
3. **Compare against a package that works** (crDroid v12.12-livefix here). But mind the limits of that conclusion:
   crDroid's shim works because **its framework also reads V2**;
   on a V4 tree the same approach fails, so the HAL must write the current layout.
4. **Under `-fno-exceptions`, any `std::` throw is an abort**.
   Copying a layout-mismatched struct by value costs you a SIGABRT.
5. **After changing a HAL, confirm the ABI first**: which register holds the return value, and that struct returns use x8.
   The function body can be entirely right and still crash on a wrong signature.
6. **Think through what a degrade path means**: SDM's null display is a degrade for composer
   but fatal for livedisplay, so the same `Init()` failure means different things to different callers.
