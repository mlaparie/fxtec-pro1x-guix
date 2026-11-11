# Fingerprint reader: what Android does, mapped for a mainline driver

State (2026-11-11): **the pieces are written, not yet run on the phone.** moWerk has
enrolment and unlock working on SailfishOS with the same driver and three kernel fixes
(sailfishos-pro1x-mainline, `notes/fingerprint.md`); this port now carries those fixes and a
daemon of its own (below).  The rest of this file is the map that got there, read from the
stock vendor blobs (as extracted by LineageOS into TheMuppets/proprietary_vendor_fxtec_pro1x,
branch `lineage-21`) with radare2 and r2ghidra, and from the GPL vendor kernel (LineageOS
android_kernel_fxtec_sm6115).  No blob is in this repository; they are proprietary.

## On Guix

| piece | what |
|---|---|
| kernel | `pro1x-qseecom-tee` (Dawid Wróbel's driver, module `qseecomtee`) and moWerk's fixes `pro1x-tzmem-bridge-errno`, `pro1x-qseecom-listener-rounds`, `pro1x-qseecom-inout` |
| services | `qsee-supplicant`, `qsee-app-loader-mafp`, `pro1x-fpd` (`services/fingerprint.scm`, not started at boot until that kernel runs) |
| daemon | `pro1x-fpd/`: the TA protocol of moWerk's sailfish-fpd-mafp in C; `/run/pro1x-fpd.sock`, line protocol in the file's header; the same binary is the client (`pro1x-fpd list`) |
| lock screen | `gtklock-fingerprint/`, a gtklock module loaded by `pro1x-lock` while the daemon runs: one identify while gtklock is up, gtklock quits on a match |
| enrolment | quick actions' Fingerprints (`device/sway/pro1x-fingerprint`): add (14 touches), rename, remove; up to five fingers |

Not reading the sensor all the time: nothing polls it but an identify or an enrolment.  The
lock screen's identify lasts as long as gtklock, and pauses while the panel is off (DPMS), so
the sensor is read only on a lit lock screen, every 100 ms until a touch.  Open: the sensor
interrupt (TLMM 97) instead of polling; the sensor's power stays on while the daemon runs;
recovering a dead TA instance (moWerk saw one once: restart `qsee-app-loader-mafp`, then
`pro1x-fpd`); the match rate (about one touch in three on his phone).

**Never run `pro1x-fpd` on a kernel without the tzmem and listener fixes** once more than
one finger is on file: set_active_group then reads past 256 listener rounds and the phone
hangs hard (moWerk's three hangs of 2026-11-09).

## The stack on Android

| layer | file | role |
|---|---|---|
| kernel | `drivers/input/fingerprint/madev.c`, `qcom-settings.c` (GPL, MicroArray v4.0.05) | built with `TEE` and `USE_PLATFORM_DRIVE`: powers the sensor, forwards its IRQ, wake locks, `/dev/madev0` ioctls. No SPI access. |
| device tree | `microarray_fp`, compatible `microarray,fingerprint` | reset `tlmm 104`, IRQ `tlmm 97`, power `tlmm 108`, `suben` `tlmm 67` |
| trusted app | `/vendor/firmware/mafp.mbn` (32-bit ARM, QSEE) | owns the SPI bus (`qsee_spi_open`), captures, enrolls, matches, stores templates through QSEE's secure file system (`qsee_sfs_*`, files `group-%d-template-%d.data`) |
| client library | `/vendor/lib64/libfprint-x64.so` | MicroArray's library (`bio_*` API for the HAL, `ma_tac_*` for the TA) |
| HAL | `/vendor/lib64/hw/microarray.fingerprint.default.so` | thin wrapper over `bio_*` |
| Qualcomm | `libQSEEComAPI.so`, `qseecomd` | load the app, send commands; qseecomd serves the TA's listeners (file system, RPMB, time) |

## Transport

- App name `mafp`, loaded whole from `/vendor/firmware/mafp.mbn` with
  `QSEECom_start_app_V2` (one image in a buffer, not the split `.mdt`/`.bNN`).
  Shared buffer 0x20000 bytes.
- Every call is `QSEECom_send_cmd(handle, buf, 0x20000, buf, 0x20000)` with
  `buf = [u32 command][u32 length][payload]`; the reply overwrites the payload in the
  same buffer. One mutex around it. No encryption on this path (the library's AES
  code is for tokens, not the transport).
- `ma_tac_service_init` (0xC9) checks the TA's git tag against the library's,
  `abc068b05c329448182ee5ea66bf85f9889eb37a` (TA version string
  `v4.1.9.197_abc068b0`).

## Commands (payload size in bytes, from the callers)

| id | function | size | | id | function | size |
|---|---|---|---|---|---|---|
| 0xC8 | init | 0x408 | | 0xDD | save_paras | 8 |
| 0xC9 | service_init / set / update config | 0x180 | | 0xDE | init_navigate | 8 |
| 0xCA | set_active_group | 0x154 | | 0xDF | navigate_tap | 8 |
| 0xCD | pre_enroll | 8 | | 0xE0 | navigate_direction | 8 |
| 0xCE | enroll_start | 0x48 | | 0xE1 | reset_interrupt_para | 8 |
| 0xCF | do_enroll | 0x16810 | | 0xE2 | enumerate | 0x20 |
| 0xD0 | enroll_finish | 8 | | 0xE3 | read_line | 8 |
| 0xD1 | cancel | 8 | | 0xE4 | spi_test | 8 |
| 0xD2 | detect_touch | 0x16808 | | 0xE5 | deadpixs_test | 8 |
| 0xD3 | detectTouch_getEnergy / press_test | 0x3C0C | | 0xE6, 0xE7 | interrupt_test | 8 |
| 0xD4 | get_energy | 0x16814 | | 0xE9–0xEE | factory enroll, authenticate, remove, image, temp pic, vendor | 8 or 0x20008 |
| 0xD5 | do_verify | 0x16860 | | 0xEF | factory_get_chipid | 0xC |
| 0xD6 | update_authenticate_data | 4 | | 0xF0–0xFA | factory and SPI tests | up to 0x20008 |
| 0xD7 | remove | 0x20 | | 0xF1 | update_config | 0x180 |
| 0xD8 | has_calibrate | 8 | | 0xFB | get_auth_id | 0xC |
| 0xD9 | calibrate | 8 | | 0xFC | sensor_power_down | 8 |
| 0xDA | calc_interrupt_para | 8 | | 0xFD | sensor_increase_interrupt_th | 8 |
| 0xDB | sleep / reverse_sleep | 8 | | 0xFE | sensor_reset_interrupt_th | 8 |
| 0xDC | reverse_wakeup | 8 | | | | |

`ma_tac_update_template` is empty: the TA saves templates itself.

## What mainline lacks

1. Loading a TA: mainline `qcom_qseecom` only looks up apps firmware already loaded,
   and on this phone it is not even created (`qseecom: untested machine, skipping`,
   version 0x1402000).
2. A way for userspace (or a kernel client) to send this command buffer.
3. Listeners: the TA's `qsee_sfs_*` calls come back to Linux as listener requests
   (qseecomd's file system service, and probably RPMB). Without them, enrolling
   most likely fails when the TA saves a template (inferred, not tested).
4. The sensor's power and reset GPIOs and IRQ, and a libfprint driver on top.

## Plan

1. (done) Map the protocol, this file.
2. (done 2026-11-06, `qsee-probe/`, a module loaded by hand, no reboot)
   - Lookup works under mainline: `keymaster64` is app 1, `qcom.tz.uefisecapp` app 2,
     both loaded by the bootloader; `mafp` is not loaded.
   - Starting `mafp` (raw QSEE OS app start, `.mdt` + `.b00`..`.b07` in a tzmem
     buffer, SHM bridge mode) fails: status -2 (`QCOM_SCM_EINVAL_ADDR`), result -47.
     The phone stayed up.
3. Not cmnlib (corrected 2026-11-06): the vendor DT's `qcom,appsbl-qseecom-support`
   tells the vendor driver that the bootloader loaded `cmnlib`, and
   `qcom,commonlib64-loaded-by-uefi` the same for `cmnlib64`. The stock firmware
   flashes the `cmnlib` partitions empty, and its vendor partition has no `cmnlib`.
   The image layout matches the vendor's. Open: the memory. The vendor loads from its
   `qseecom_mem` reserved region, registered with TrustZone as an SHM bridge at probe;
   mainline's tzmem pool is bridged too (`qcom_tzmem_using_shm_bridge` is 1 on the
   phone), so that is not it either. Cause of the -2: open. The module's `lib=`
   parameter is not needed.
   Mainline's newer QTEE driver (`qcomtee`, object interface) is no way round:
   `qcom_scm` created no `qcomtee` device on this TrustZone (its probe call is
   refused), although the module is built.
3b. (2026-11-06) The app loads, but does not take commands yet.
   - Loading needs the image at a 4 MiB-aligned address (the test module got -2
     at 0xfe200000, status 0 at 0xfe400000); Dawid Wróbel's QSEECOM TEE driver
     (kernel patch `pro1x-qseecom-tee`) does it, and loads `mafp.mbn` whole.
   - With that driver (branch `dev-fingerprint`, generation 27): `qsee-supplicant`
     registers listeners 10 and 28672, `qsee-app-loader mafp` loads the app,
     and a session opens; every command (`mafp-client 0xef 0xc`, buffers from
     0x14 to 0x20000 bytes) fails in the send call: `scm call failed with
     error -22`. Same with the test module. Open.
   - (2026-11-07) What the -22 is: mainline prints `scm call failed` only when the
     secure monitor's own status is an error (`qcom_scm_remap_error`: invalid
     address, invalid argument, or an unknown code), so TrustZone refuses the call
     before the app sees it; the app's protocol is not what fails here.
   - Not the 4 GiB limit: the vendor driver refuses a 32-bit app's buffers above
     4 GiB, but mainline's TZ memory keeps the platform device's default 32-bit DMA
     mask (`qcom_scm` sets none); the test module's request and reply were at
     `0xfe300000` and `0xfe320000` (`app_id=3 cmd=0xef cmd_len=0xc`), still -22.
   - Not the request format: the library only uses `QSEECom_send_cmd` (no modified
     command, no ion buffers), so no physical address goes inside the request.
   - Left (inferred): the call itself. With the whitelist feature, the vendor
     driver sends app commands with `TZ_APP_QSAPP_SEND_DATA_WITH_WHITELIST_ID`
     (command 6, two more arguments: an sglist table and its size) instead of
     command 1, which mainline uses.
   - (2026-11-07) Command 6 tried (test module, `whitelist=1`): TrustZone has the
     whitelist feature (version 0x401000), and the call fails too, differently:
     status -2 (`QCOM_SCM_EINVAL_ADDR`), result -19, with the request, reply and an
     empty 32-byte sglist table in mainline TZ memory below 4 GiB. The phone stayed
     up. So the call variant alone is not it: TrustZone rejects an address.
   - (2026-11-07) Mainline's call and memory do work on this TrustZone: the test
     module's `uefi=1` sends QueryVariableInfo to `qcom.tz.uefisecapp` (app 2,
     loaded by the bootloader) with command 1, laid out as mainline's
     `qcom_qseecom_uefisecapp`, and gets a proper reply (status 0, storage 20480,
     free 20024), from a one-page block at 0x67b4b000 and from two pages at
     0xfe300000 alike. `mafp` with the same small layout (`buf_size=0x20`, at
     0xfe300000) still fails. So it is `mafp`, not the call or the memory.
   - (2026-11-09, reported by moWerk from the blobs, not checked here) The app
     registers in TrustZone as `fingerprint`, not `mafp` (`n=fingerprint` in its
     metadata), so a lookup of `mafp` fails even while it runs.  It is a copy of
     Qualcomm's `smplap32` sample (same UUID), so the two may clash if both load
     in one boot.  Android sends 0xC8 and 0xC9 first, and our tests began with
     0xEF: the app may fault on an uninitialised sensor context, which would
     show as the SCM error and make "TrustZone refuses the call" above wrong.
     There is no clock or bandwidth vote in the stock stack.
   - (2026-11-09, confirmed on this phone, kernel 7.3.0) The order is what matters.
     With 0xC8 (len 0x408), then 0xC9 (0x180), then 0xEF (0xc), each from a new
     `mafp-client` process and with all-zero payloads, all three return ret 0,
     with no SCM error.  After reloading the app, 0xEF first fails with -22 as
     before.  So the "TrustZone refuses the call before the app sees it" reading
     above was wrong: the -22 comes from the app's uninitialised state.  Every
     reply is all zeros, including the chip id from 0xEF, so the sensor has not
     been shown to answer: the zero payloads may not be a valid init.  Not tested:
     which of 0xC8 and 0xC9 is needed.  The name `mafp` opened a session here.
   - (2026-11-09, confirmed, `qsee-probe same_buf=1`) The app answers in place, as
     Android's single buffer implies: with one buffer for request and reply the
     send works in the 0xC8, 0xC9, 0xEF order, and 0xC9 leaves status 0xfffff382
     (-3198) at payload offset 0x150, the field `ma_tac_service_init` checks.
     Separate buffers (the TEE driver's layout) lost this, so the replies read
     as zeros.  The git tag at 0x154 stays empty.  -3198 is not yet explained:
     blank payloads and the unpowered sensor are the candidates.  From the
     library: 0xC8's payload is `[g_driver_version][length][bytes of length]`,
     and 0xC9's is a 0x14c-byte config passed by the caller.
   - (2026-11-09, confirmed) The sensor answers.  With `gpioset -c gpiochip2 -z
     108=1` held, the app loaded, `qsee-probe same_buf=1 gcc_clks=91,90,102`, and
     0xC8, 0xC9, 0xEF sent in that order with blank payloads, 0xEF replies 0x24
     (36) in its first payload word: the chip id, and the library lists E36
     among its sensors.  Power is what matters: GPIO 108 alone gives the same
     result, and the QUP5 clocks without it still give -3198.  The -22s and all-zero replies before were 0xEF first
     and the separate reply buffer.
   - (2026-11-09, confirmed) With a finger held on the sensor, 0xD2 detect_touch
     (0x16808) and 0xD3 press_test (0x3c0c) after 0xC8, 0xC9, 0xEF return ret 0
     and no data, and the IRQ line 97 read inactive before them.  No comparison
     without a finger yet.  Android's `bio_init` does more first (config, active
     group, calibration), and our 0xC9 config is blank.
   - (2026-11-09, confirmed) With the config decoded from `init_properties`
     (`qsee-probe words=`), 0xC9 echoes it and returns status 0.  0xD9 calibrate,
     0xD2 and 0xD3 return ret 0, with and without a finger, and read the same.
     Inconclusive: the probe prints only the first 0x180 bytes of the reply, and
     the data of 0xD2 (0x16808 bytes) may be past that.  0xCA was not sent.
   - App 3 exists for TrustZone: with command 6, `mafp` gets result -19 and a
     non-existent app id (99) result -2 (both status -2; with command 1 both
     -22). `mafp` is still not found by name lookup.
   - No `cmnlib` to load: `cmnlib_a/b` and `cmnlib64_a/b` are all zeros on the
     phone (read only), the vendor tree has no image, yet the 64-bit apps run;
     `tz.mbn` holds the strings `cmnlib`, `cmnlib64`, `cmnlib_init`, so both are
     most likely built into this TrustZone (inferred). Open: what result -19
     means, and whether Linux-loaded or 32-bit apps take commands here at all.
   - (2026-11-07) Other mainline QSEECOM fingerprint ports (reported): Wróbel's
     Xiaomi (Goodix), samcday's Pixel 3a (sargo, FPC, a 64-bit TA;
     samcday/pocketfed#116, samcday/sargo-bible#1), michaelmcallister's Moto G10
     (SM4250; wrobelda/qsee-supplicant#1, RPMB listener). On the Pixel the TA
     declares `DT_NEEDED libcmnlib.so` and its load fails unless Linux first loads
     `cmnlib64` (from `/vendor/firmware`, APP_MGR command 7). `mafp` declares
     `libcmnlib.so` too (it has a "Failure in cmnlib_init()" message), yet loads
     here: another sign that this TrustZone has cmnlib built in (inferred).
     Asked: wrobelda/qsee-supplicant#2.
   - (2026-11-07) Linux-loaded 32-bit apps do take commands: Qualcomm's sample
     apps from the modem partition (`image/smplap32.*`, `smplap64.*`, both linking
     `libcmnlib.so`), loaded by the test module (`image=`, `.mdt` + segments) as
     apps 5 and 4, accept command 1 through mainline's send with status 0;
     `smplap32` replies 0x50 to data 8 (×10). So neither the 32-bit class, cmnlib,
     loading from Linux nor mainline's send is the cause: it is `mafp`. Lead
     (inferred): -19 is ENODEV, and `mafp` owns the sensor's SPI bus; on Android
     `madev.c` powers the sensor before the app loads, here nothing does. Next:
     power the sensor (power `tlmm 108`, `suben` `tlmm 67`, reset `tlmm 104`),
     then load `mafp` and send 0xEF.
   - (2026-11-07, reported by michaelmcallister, wrobelda/qsee-supplicant#1)
     The Moto G10 (SM4250) has the same QSEE version, 0x1402000, and commands to
     its 64-bit TA (Chipone ICNF7332, `fngap644`) work through plain
     `qcom_scm_qseecom_app_send()`; his driver changes were for loading (64-bit
     MDT parsing); no cmnlib loading. Same conclusion: the platform takes the
     send, `mafp` is refused.
   - (2026-11-07) Sensor power alone is not it. The vendor driver's only power
     step is `gpio_pwr` high then 10 ms (`qcom-settings.c`; reset and the
     regulator are unused). With `gpioset -c gpiochip0 -z 108=1` held, `mafp`
     loaded (app 6) and 0xEF still failed with -22; the IRQ line (97) stayed
     inactive. Before the test, 104 and 108 showed `egpio` in debugfs and no pin
     was claimed.
   - (2026-11-07) The sensor's SPI bus is most likely QUP SE5 (`spi@4a94000`,
     pins GPIO 14-17, function `qup5`): the vendor DT declares it but disables it
     for Linux, as for a bus TrustZone owns, and has no SPI node for the sensor.
     Mainline leaves it alone too: the node is disabled, GPIOs 14-17 are in
     `gpio-reserved-ranges` (`<0 4 14 4>`), unclaimed. But mainline turns off the
     clocks no Linux driver holds: `gcc_qupv3_wrap0_s5_clk` and the wrapper's
     `core`/`core_2x` were off. The test module's `gcc_clks=91,90,102` kept them
     on (enable count 1), with the sensor powered, while `mafp` loaded (app 7):
     0xEF still failed with -22. Not the cause, or not alone.
4. Power the sensor from the DT GPIOs and check its IRQ on a touch (no TrustZone).
5. Send 0xC8, 0xC9 and read the chip ID (0xEF).
6. Listeners for the TA's file storage; then enroll and verify structures.
7. A libfprint driver, so fprintd, PAM and the lock screen can use it.
