# Hibernation: status (2026-11-19)

Branch `dev-hibernate`. Not in `main`: there the power menu has no
Hibernate line and nothing hibernates on its own.

## Summary

The image is saved and restored. The system does not survive the restore:
the cold boot in between resets the DSPs (modem, ADSP, CDSP) and some PMIC
blocks, while the restored kernel still takes them for running. User space
hangs within a second of the restore.

## What works (confirmed on the phone)

- Swap file of 8 GiB in `/swap` (btrfs), `resume=/dev/mapper/pro1x-crypt`
  with `resume_offset` from `btrfs inspect-internal map-swapfile`.
- The LUKS container is mapped through dm-linear (`device/fde/dm-offset.c`),
  not a loop device. The loop device's workqueue is freezable: it hung the
  first image write. The plain boot area is mapped the same way
  (`/dev/mapper/pro1x-boot`), because a dm mapping holds the partition.
  These two changes are in `main` too: they work and do no harm.
- Freezing: `smp2p_sleepstate` is unloaded and QRTR's `wake_on_data` is off
  while hibernating. Each turned wakeups into aborts.
- `pm_test` devices, processors and core all pass; `test_resume` restores.
- A real hibernation: "Image saving progress" up to 100 %, power-off (with a
  charger: a reboot, red LED), then the boot's initrd finds the image and
  restores it ("Hibernation image restored successfully").
- The GPU loads its zap shader again after the restore (kernel patch
  `pro1x-adreno-zap-hibernate.patch`); without it every submit faulted.
- The LED breathes while the phone is hibernated (the LPG pattern trigger
  needs `repeat` set to -1).

## What fails

1. With every driver loaded, the device restore takes 46 s: ath10k (Wi-Fi)
   and Bluetooth wait for firmware that the power-off removed. The PMIC
   temperature alarm interrupt then fires without end ("irq 132: nobody
   cared"), PM6125 ADC reads fail (`0x0 0x3150: transaction failed`), and
   user space stalls before the DSPs can be restarted.
2. With Wi-Fi, Bluetooth, the temperature alarm and the ADC users unloaded
   before the image (`pro1x-sleep` on this branch), the restore takes 1 s.
   User space hangs right after it: the console stops at "Restarting tasks:
   Done", and nothing more is logged.

Inferred cause of 2: the restored kernel still holds live links to the DSPs
(glink in shared memory, maybe a hardware spinlock), which the cold boot
reset. Not confirmed.

## Ruled out

- The SPMI arbiter's APID map: identical on every cold boot (read through
  `/dev/mem`).
- Restarting the DSPs from user space after the restore: user space never
  gets that far.
- Stopping the DSPs before the image: on a running phone, a CDSP stop and
  start passes, but an ADSP stop and start freezes the phone within 10 s
  (2026-11-19, with the author's OK). The modem was not tried.

## Next (kernel work)

- Find what hangs after an ADSP stop and start on a running phone. It
  happens without hibernation, and fixing it would also fix ADSP crash
  recovery. Suspects: the q6 audio drivers, fastrpc and its clients
  (hexagonrpcd, the sensors).
- Then stop the DSPs before the image and start them after the restore, so
  that the restored kernel's view matches the hardware.
- Give the PMIC temperature alarm and ADC drivers restore callbacks instead
  of unloading them.

## Tools on this branch

- `pro1x-sleep hibernate`: the whole sequence (LED, unloads, wakeup sources
  off, `disk`, DSP restart, reload).
- Debugging: `echo N > /sys/module/printk/parameters/console_suspend`,
  `dmesg -n 8`, `chvt 2; setterm --msg on --msgredirect 2`. The kernel
  messages then show on VT2 during the write and the restore. The system
  log freezes at "hibernation entry", so this screen is the only record.
- Kernel patches: `sleepstate-hibernate`, `hibernate-debug` (ramoops,
  progress lines), `adreno-zap-hibernate`. They are still in `main`'s
  kernel, which they leave unchanged unless it hibernates; they leave
  `main` with its next kernel build.
