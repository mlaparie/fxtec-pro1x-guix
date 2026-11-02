# Kernel 7.3 series (branch `kernel-7.3`)

Patches for mainline v7.3 (kernel.org tarball), applied in file-name order,
then ours from `../patches/` (see `modules/fxtec-pro1x/packages/kernel.scm`).

Origin: moWerk's SailfishOS mainline port of the Pro1-X,
github.com/moWerk/sailfishos-pro1x-mainline, `kernel/patches-7.3/`, copied
on 2026-11-02 (GPL-2.0, as the kernel), unchanged but for one comment:
0010 writes the fixed, locally administered Bluetooth address of its
local-bd-address with spaces instead of colons (the repository's privacy
hook refuses MAC-shaped strings; the value is the same on every phone,
the DT line under it unchanged).  What each patch does and
its upstream status: that repository's `kernel/HANDOVER.md`.  0001-0011 are
the NixOS port's device patches (nyymi609/fxtec-pro1x-nixos) rebased by him;
0029, 0032-0034, 0038 come from the Lenovo TB-J606L port (haltia-de).

Left out:
- 0012 sfos-dt: SailfishOS-only (Fn as KEY_RIGHTALT, the slide switch
  inverted for mce), which our keyd and slider helpers do not expect; and
- 0028, which only undoes 0012's keyboard backlight inversion;
- 0050, 0051, 0056: experimental in his tree (system power domain under the
  MPM, SPMI through the MPM, UFS power-down needed with them), not in his
  daily kernel.  The deep-sleep step, after this base works.

Ours on top (`../patches/`): panelgap, dpugap (NixOS port, module
parameters, off by default), qrtr-modem-wake (v4).  Dropped from our 7.1
list: q6v5-handover (7.3 no longer logs the repeated handover),
charge-control (his charging_enabled attribute replaces it; userspace uses
either), fastrpc-*, panel-display-off, imx582-1080p, dw9800-soft (his 0033,
0034, 0023, 0014, 0015).

Config: config.aarch64 (7.1) plus ../pro1x-7.3.fragment, through 7.3's
olddefconfig.  Checked locally (x86 host compiler): every option of
pro1x.fragment and pro1x-7.3.fragment survives; lost from the 7.1 config,
besides compiler-capability flags (an artefact of the host compiler):
CRYPTO_DEV_QCE*, CRYPTO_DEV_QCOM_RNG (dependencies changed in 7.3; not
needed to boot), PROC_SYSCTL (to check: renamed or merged in 7.3).

State: the patched source builds (guix build -S, 2026-11-02); the kernel
not yet built (CI on this branch).
