# Troubleshooting

## The phone does not come back after an update

Hold **volume-down** at power-on, pick an older generation in the U-Boot
menu, then `sudo guix system roll-back` or fix the configuration.

## No SSH over USB

- `ip addr` on the PC: the phone's link should get an address next to
  172.16.42.1.
- Host key changed after a reflash: `ssh-keygen -R 172.16.42.1`.
- Deploy refused as root: the PC's key is not in `/root/.ssh/authorized_keys`
  ([install.md](install.md#5-connect)).

## Logs

| what | where |
|---|---|
| services | `sudo herd status`, `sudo herd status <service>` |
| system and daemons | `/var/log/messages`, `/var/log/*.log` (one per Pro¹x service) |
| sessions | `/tmp/phosh-1000.log`, `/tmp/sway-1000.log`, `/tmp/sxmo-1000.log` |
| kernel | `sudo dmesg` |
| modem | `mmcli -m 0`, `/var/log/ModemManager.log` |

There is no journalctl: no systemd.

## Known problems

- **No sound, only "Dummy Output":** check `sudo dmesg | grep "fatal
  error"`.  An ADSP crash (sensor core) takes audio with it until reboot.
- **Slower after some hours (Sway):** swaybar leaks memory (about
  0.5 GB an hour with the port's bar; being investigated).  Super+Shift+r
  reloads Sway, which restarts the bar and frees it.
- **LTE:** seen once, not confirmed; 3G works.
- **Settings refuse with "not authorized":** there is no logind; the port
  allows its user through polkit rules for the modem, network and sensors.
  Report other actions.
- **Brightness:** never read `/sys/class/backlight/*/actual_brightness`
  in a script or status bar: it wedges the panel (white screen until
  reboot).
- **Clock at 1970 after boot:** TLS and `guix pull` fail until ntpd sets
  it, once the network is up.

## Never

- Do not erase or restore `persist`, `modemst1/2`, `fsg`, `fsc`
  partitions: they hold the unit's calibration and IMEI.
- Do not stop the modem remoteproc to reset it: reboot.
