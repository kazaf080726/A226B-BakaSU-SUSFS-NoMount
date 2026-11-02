> 🌐 **English** | [中文（默认）](NOTICE.md)

# NOTICE — third-party code and licences

This project is a **Linux 4.14.186 kernel integration repository for the Samsung Galaxy A22 5G
(SM-A226B)**: free, public, actively maintained and buildable by anyone. Most files come from Samsung's
official open source kernel; the rest are build scripts, configuration and ported code added here.

## Licence overview

| Part | Licence | Origin |
|---|---|---|
| Samsung 4.14.186 kernel source | GPL-2.0 | Samsung Open Source Release Center |
| Build scripts, README and patches of this project | GPL-2.0 | this repository |
| BakaSU (kernel driver part) | GPL-2.0 | https://github.com/Baka-SU/BakaSU |
| BakaSU manager APK | GPL-3.0 | same, not included here |
| SUSFS v2.3.0 | GPL-2.0 | https://gitlab.com/simonpunk/susfs4ksu |
| NoMount (kernel part) | GPL-2.0 | https://github.com/maxsteeel/nomount |
| NoMount metamodule / WebUI | GPL-3.0 | same, not included here |
| PathMask | GPL-2.0 | https://github.com/Andrea-lyz/LKM-PathMask |
| KPatch-Next kpimg/kptools | GPL-2.0 | https://github.com/KernelSU-Next/KPatch-Next |
| AnyKernel3 | see upstream | https://github.com/osm0sis/AnyKernel3 |

`LICENSE` holds the GPL-2.0 text that covers this repository's own parts and the kernel source; the
upstream components remain under the licence of their own repositories.

## Free of charge and redistribution

- Official releases of this project are free forever: no paid version, no paid service, no licence key.
- Forking, modifying, self-building and redistributing are allowed, provided that you:
  - comply with the GPL licence of each component;
  - keep the original authors, source links and this NOTICE;
  - do not claim it as an official paid exclusive build, and do not remove copyright notices.

## Disclaimer

- Flashing, unlocking the bootloader and modifying the boot partition carry risk: data loss, a device
  that will not boot, or a permanently tripped KNOX.
- This project is provided "as is", without any express or implied warranty. You use it at your own risk.
- PathMask explicitly states that it must not be used to circumvent game anti-cheat; follow its upstream
  disclaimer.
- Samsung, KNOX, BakaSU, SUSFS, NoMount, PathMask and KPatch-Next are names and trademarks of their
  respective owners.
