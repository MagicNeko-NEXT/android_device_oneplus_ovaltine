# Copyright (C) 2021-2025 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

# AAPT
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi

# Alert slider
PRODUCT_PACKAGES += \
    KeyHandler \
    tri-state-key-calibrate

# Audio
# 10T (CPH2415) audio XML comes from the 10T itself (old ovaltine tree);
# file names differ from the 10 Pro (wly): ODM-side mixer_paths.xml / resourcemanager.xml,
# and the 10T tree has no sound_trigger_*.xml (don't copy from wly).
QCV_FAMILY_SKUS := taro cape

PRODUCT_COPY_FILES += \
$(foreach DEVICE_SKU, $(QCV_FAMILY_SKUS), \
    $(LOCAL_PATH)/audio/mixer_paths.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio/sku_$(DEVICE_SKU)/mixer_paths_waipio_mtp.xml \
    $(LOCAL_PATH)/audio/resourcemanager.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio/sku_$(DEVICE_SKU)/resourcemanager_waipio_mtp.xml)

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/backend_conf.xml:$(TARGET_COPY_OUT_ODM)/etc/backend_conf.xml \
    $(LOCAL_PATH)/audio/mixer_paths.xml:$(TARGET_COPY_OUT_ODM)/etc/mixer_paths.xml \
    $(LOCAL_PATH)/audio/resourcemanager.xml:$(TARGET_COPY_OUT_ODM)/etc/resourcemanager.xml \
    $(LOCAL_PATH)/audio/usecaseKvManager.xml:$(TARGET_COPY_OUT_ODM)/etc/usecaseKvManager.xml \
    $(LOCAL_PATH)/audio/usecaseKvManager.xml:$(TARGET_COPY_OUT_VENDOR)/etc/usecaseKvManager.xml

# Boot animation
TARGET_SCREEN_HEIGHT := 2412
TARGET_SCREEN_WIDTH := 1080

# Display
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/display_id_4630947180710147970.xml:$(TARGET_COPY_OUT_VENDOR)/etc/displayconfig/display_id_4630947180710147969.xml

# oplus_udfps is declared as bool_variables in the qtidisplay namespace → soong_config_set_bool is required
# (the wly tree uses soong_config_set, the string form, which doesn't match the bool declaration; don't copy it)
$(call soong_config_set_bool,qtidisplay,oplus_udfps,true)
# 10T (ovaltine) has no Pixelworks iris hardware, so pxlw_vendor_namespace isn't set;
# otherwise the soong_config select in hardware/qcom-caf/sm8550/display requires libpwirisfeature.

# Fingerprint
# Back to the LineageOS upstream approach (used by both sm8350 and sm8450):
#   hardware/oplus/hidl/fingerprint provides the HIDL 2.3 service, the framework still has the
#   .../biometrics/sensors/fingerprint/hidl path (A16 didn't remove HIDL fingerprint support),
#   and hardware/interfaces/biometrics/fingerprint/2.1|2.2|2.3 are all present.
#
# avium previously commented this line out and used a custom AIDL proxy (device/oneplus/ovaltine/
# fingerprint), but that proxy never worked end to end: createSession against the stock HAL gives
# BAD_TYPE, and the framework doesn't catch the exception, so a dummy session had to absorb it.
#
# About the "missing VINTF declaration causes SIGSEGV" comment: cause and effect are reversed. If the service isn't in
# PRODUCT_PACKAGES -> it's not in the output -> its own vintf_fragments aren't merged ->
# the manifest naturally has no fingerprint. Once enabled, vintf_fragments merge automatically.
# The stock HAL is restored to the original (registers IFingerprint/default in odm, see
# vendor/oneplus/ovaltine/proprietary/odm/etc/vintf/manifest/
# manifest_oplus_fingerprint_aidl_v2.xml), and the framework connects to it directly,
# with no need for the HIDL 2.3 service or the AIDL proxy.
# Evidence: in crDroidAndroid-16.0-20261012-ovaltine-v12.12-livefix.zip
# fps_hal registers /default, there is no 2.3-service rc, and fingerprint works.
# PRODUCT_PACKAGES += \
#     android.hardware.biometrics.fingerprint@2.3-service.oplus

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.fingerprint.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.fingerprint.xml

$(call soong_config_set,surfaceflinger,udfps_lib,//hardware/oplus:libudfps_extension.oplus)

# ---- crDroid-specific parameters ----------------------------------------------
# TARGET_HAS_UDFPS
#   Used by: vendor/addons/config.mk:22 `ifeq ($(TARGET_HAS_UDFPS),true)`
#           → PRODUCT_PACKAGES += UdfpsIcons UdfpsAnimations
#   This is a crDroid-only switch: stock LineageOS has no vendor/addons and nothing in the source uses it;
#   unset defaults to off, and fingerprint still unlocks, just without crDroid's icon/animation skin.
#   Device evidence: 10T (ovaltine) has an optical under-display sensor, overlay/OPlusFrameworksResTarget is set from
#           persist.vendor.fingerprint.optical.sensorlocation=540::2182 for
#           config_udfps_sensor_props, and the SystemUI dim layer and brightness table are hand-tuned.
#   Form follows upstream crdroidandroid/android_device_oneplus_salami device.mk:33.
TARGET_HAS_UDFPS := true
# -----------------------------------------------------------------------------

# NFC
PRODUCT_PACKAGES += \
    android.hardware.nfc-service.nxp \
    com.android.nfc_extras \
    Tag

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.nfc.ese.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.ese.xml \
    frameworks/native/data/etc/android.hardware.nfc.hce.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.hce.xml \
    frameworks/native/data/etc/android.hardware.nfc.hcef.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.hcef.xml \
    frameworks/native/data/etc/android.hardware.nfc.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.xml \
    frameworks/native/data/etc/android.hardware.se.omapi.ese.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.se.omapi.ese.xml \
    frameworks/native/data/etc/android.hardware.se.omapi.uicc.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.se.omapi.uicc.xml \
    frameworks/native/data/etc/com.android.nfc_extras.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/com.android.nfc_extras.xml \
    frameworks/native/data/etc/com.nxp.mifare.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/com.nxp.mifare.xml \
    vendor/oneplus/sm8450-common/proprietary/vendor/etc/libnfc-nxp.conf:$(TARGET_COPY_OUT_VENDOR)/etc/libnfc-nxp.conf \
    vendor/oneplus/sm8450-common/proprietary/vendor/etc/libnfc-nci.conf:$(TARGET_COPY_OUT_VENDOR)/etc/libnfc-nci.conf \
    vendor/oneplus/sm8450-common/proprietary/vendor/firmware/sn100u.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/sn100u.bin

# Overlays
DEVICE_PACKAGE_OVERLAYS += \
    $(LOCAL_PATH)/overlay-custom

PRODUCT_PACKAGES += \
    OPlusFrameworksResTarget \
    OPlusSettingsProviderResTarget \
    OPlusSettingsResTarget \
    OPlusSystemUIResTarget

# Power
$(call soong_config_set,qtipower,mode_ext_lib,power-ext-oplus)

# PowerShare
PRODUCT_PACKAGES += \
    vendor.lineage.powershare-service.oplus

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)

# Inherit from the common OEM chipset makefile.
$(call inherit-product, device/oneplus/sm8450-common/common.mk)

# Inherit from the proprietary files makefile.
$(call inherit-product, vendor/oneplus/ovaltine/ovaltine-vendor.mk)

# No camera app is preinstalled: users choose their own.
PRODUCT_PACKAGES += \
    OvaltineRemoveCameraApp

# vendor/extra (LineageOS community extras): PRODUCT_ADB_KEYS whitelists a
# public key for adbd, iperf3/tinymix
# are handy on-device tools. ih8sn and GMS stay off unless asked for.
$(call inherit-product-if-exists, vendor/extra/product.mk)

# Third-party Adreno graphics stack (Meta Quest 3 V@0837.0.7).
# Off by default for bring-up. BoardConfig.mk owns the same variable and the
# two must agree; passing GPU_DRIVER_Q3=true swaps out the OEM graphics modules. The OEM blobs stay untouched either way, so falling back needs no
# git operations.
GPU_DRIVER_Q3 ?= false
ifeq ($(GPU_DRIVER_Q3),true)
GPU_OEM_GRAPHICS_MODULES := \
    eglSubDriverAndroid \
    libEGL_adreno \
    libGLESv1_CM_adreno \
    libGLESv2_adreno \
    libq3dtools_adreno \
    libq3dtools_esx \
    libVkLayer_ADRENO_qprofiler \
    vulkan.adreno \
    libadreno_app_profiles \
    libadreno_utils \
    libCB \
    libgsl \
    libkcl \
    libkernelmanager \
    libllvm-glnext \
    libllvm-qcom \
    libllvm-qgl \
    libOpenCL \
    vendor.qti.qspmhal

# The OEM modules must be filtered inside gpu-q3.mk: inherit-product is
# recorded here and expanded later, so filtering in this file would run
# before the OEM module list exists.
$(call inherit-product, vendor/oneplus/sm8450-common/gpu-q3/gpu-q3.mk)
endif

# Vulkan ICD switching without touching the framework.
#
# /vendor/lib64/hw/ carries vulkan.adreno.so (OEM Qualcomm) and
# vulkan.freedreno.so (Mesa Turnip). ro.hardware.vulkan no longer chooses
# between them: it points at vulkan.switcher.so, a small hwvulkan HAL module
# that adopts the real ICD named in
#   /data/misc/vulkan/per_app.conf     (writable, wins)
#   /vendor/etc/vulkan/per_app.conf    (image default, see below)
# and hands that driver's device struct to libvulkan unchanged. libvulkan itself
# is stock, so a framework update can never lose the switch.
#
#   <package>=<subname>    e.g. com.tungsten.fcl=freedreno
#   *=<subname>            default for every other process
#
# Both ICDs always ship, so any app can be moved at runtime by editing the
# /data file and force-stopping that app -- no rebuild, no reboot, no root.
#
# GPU_DRIVER_TURNIP now only picks the *image default*:
#   true            -> switcher with *=freedreno, the open-source ICD
#   false (default) -> plain OEM Adreno, no switcher (bring-up)
GPU_DRIVER_TURNIP ?= false

ifeq ($(GPU_DRIVER_TURNIP),true)
PRODUCT_PACKAGES += \
    vulkan.freedreno \
    vulkan_switcher \
    vulkan-switch \
    VulkanSwitch

# /data/misc/vulkan must be created by the init domain, so this rc goes on the
# system partition instead of next to the other vendor bits.
PRODUCT_COPY_FILES += \
    device/oneplus/ovaltine/vulkan-switcher/vulkan_perapp.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/vulkan_perapp.rc

PRODUCT_VENDOR_PROPERTIES += ro.hardware.vulkan=switcher
else
PRODUCT_VENDOR_PROPERTIES += ro.hardware.vulkan=adreno
endif
# No /vendor/etc/vulkan/per_app.conf on purpose: sepolicy neverallow
# (domain.te:2155) forbids app domains from reading vendor_file_type files.
# The switcher's image default is compiled in; runtime overrides go to
# /data/misc/vulkan/per_app.conf.

# The privileged selector app that used to rewrite /data/misc/vulkan/per_app.conf
# was not carried over into this tree; naming it here would fail the build with
# an unknown module. Until it lands, use /vendor/bin/vulkan-driver (root shell)
# or edit the file directly.
# PRODUCT_PACKAGES += VulkanDriverSwitch

# Fingerprint proxy HAL support.
# The original OPlus HAL is patched to register as IFingerprint/oplusfp (two
# instructions in its main(), pointing at a new string in a padding area of
# rodata) so this proxy can own IFingerprint/default. LD_PRELOAD was tried
# first and does not work: the environment variable is set correctly but the
# linker never maps the library.
PRODUCT_PACKAGES += \
    libshims_aidl_fingerprint_v2.oplus

# The proxy is built against fingerprint-V4-ndk because V5 is the unfrozen
# current version and vendor modules may not depend on it. The framework however
# is compiled against fingerprint-V5-java, parses SensorProps with the V5 layout
# and dies with IllegalArgumentException inside BiometricServiceRegistry, which
# boot-loops system_server. The PJG SensorProps shim only rewrites field values,
# not the parcel layout, so it cannot paper over the mismatch.
# Re-enable only once the proxy speaks V5 (freeze aidl_api/.../5 first).
# AIDL proxy disabled: no longer needed after moving to the upstream HIDL 2.3 service.
# Source kept in device/oneplus/ovaltine/fingerprint/ for future reference.
# PRODUCT_PACKAGES += \
#     android.hardware.biometrics.fingerprint-service.proxy
