#!/usr/bin/env python3
"""Make QEMU's virt DT look like the phone where first-stage init cares.

Adds the firmware/android/vbmeta node that the real cape DTB has, and moves the
PCIe host under a simple-bus "soc" node, so the USB disk's platform path is
soc/<addr> and /dev/block/platform/soc/${ro.boot.bootdevice} resolves unchanged.
"""
import sys

src, dst = sys.argv[1:3]
s = open(src).read()
i = s.index("\tpcie@")
depth, k = 1, s.index("{", i) + 1
while depth:
    depth += (s[k] == "{") - (s[k] == "}")
    k += 1
k = s.index(";", k) + 1
node = s[i:k]
s = s[:i] + s[k:]
s = s.rstrip()
assert s.endswith("};")
s = s[:-2] + """
	firmware {
		android {
			compatible = "android,firmware";
			vbmeta {
				compatible = "android,vbmeta";
				parts = "vbmeta,boot,system,vendor,dtbo,recovery";
			};
		};
	};
	soc {
		compatible = "simple-bus";
		#address-cells = <0x02>;
		#size-cells = <0x02>;
		ranges;
""" + node + """
	};
};
"""
open(dst, "w").write(s)
