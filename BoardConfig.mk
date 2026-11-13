#
# Copyright (C) 2021-2025 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Include the common OEM chipset BoardConfig.
include device/oneplus/sm8450-common/BoardConfigCommon.mk

DEVICE_PATH := device/oneplus/ovaltine

# HIDL
# 10T has two HIDL HALs, eSE/NFC and qti esepowermanager;
# sm8450-common's vintf/manifest.xml doesn't declare them, so the device must add them.
DEVICE_MANIFEST_FILE += $(DEVICE_PATH)/manifest.xml

# Partitions
# 10T's super layout follows stock: total super size matches the common default (11274289152),
# with only 900000000 B reserved on product. BOARD_ONEPLUS_DYNAMIC_PARTITIONS_SIZE is
# a dead variable left from the old tree (no references anywhere), not inherited here.
ifeq (,$(filter true, $(WITHOUT_RESERVED_SIZE) $(WITH_GMS)))
BOARD_PRODUCTIMAGE_PARTITION_RESERVED_SIZE := 900000000
endif

# Properties
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# Recovery
# 10T: 1080x2412 → xxhdpi; status bar/cutout height differs from 10 Pro (103 vs 126).
TARGET_RECOVERY_DENSITY := xxhdpi
TARGET_RECOVERY_UI_MARGIN_HEIGHT := 103

# Include the proprietary files BoardConfig.
include vendor/oneplus/ovaltine/BoardConfigVendor.mk

# vendor/extra board config
-include vendor/extra/BoardConfigExtra.mk

# Third-party Adreno driver selection (Meta Quest 3 V@0837.0.7; the files live
# in vendor/oneplus/sm8450-common/gpu-q3, wired up by that directory's own
# gpu-q3.mk).
# Off by default for bring-up, so a plain build uses the OEM stack. `?=` only
# assigns when unset, so it can be enabled from the environment with:
#   GPU_DRIVER_Q3=true
GPU_DRIVER_Q3 ?= true
$(call soong_config_set,gpu_oplus,driver_q3,$(GPU_DRIVER_Q3))

# The original fingerprint HAL is renamed to IFingerprint/oplusfp so the proxy
# HAL can register IFingerprint/default. android.* HALs using a non-standard
# instance name must be listed here or checkvintf fails the build.
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE += \
    device/oneplus/ovaltine/fingerprint/compatibility_matrix.xml

# Mesa Turnip (freedreno) Vulkan driver switch. Independent from
# GPU_DRIVER_Q3: Q3 only swaps the Adreno stack, Turnip replaces the Vulkan
# driver itself with the open-source one.
# Off by default for bring-up. Enabling it also installs the runtime switcher
# (vulkan.switcher.so, see device.mk):
#   GPU_DRIVER_TURNIP=true
GPU_DRIVER_TURNIP ?= false
$(call soong_config_set_bool,gpu_oplus,driver_turnip,$(GPU_DRIVER_TURNIP))
