#!/usr/bin/env bash
# hotspot-ab-test.sh — on the phone, as root: the hotspot's latency and speed
# with wlan0's power saving on and off, while a device (a laptop) is on the
# hotspot and wlan0 is on a network (Keep Wi-Fi).  Everything is put back as
# found when it ends, however it ends.  Log: /root/hotspot-ab.log.
#
#   scp -i ~/.ssh/pro1x-guix scripts/hotspot-ab-test.sh root@PHONE:/root/
#   ssh -i ~/.ssh/pro1x-guix root@PHONE /root/hotspot-ab-test.sh [ROUNDS]
#
# Phases, ROUNDS times (3 by default), about 40 s each: "on", the hotspot
# restarted with wlan0 in power saving (the state the hotspot ran in until
# 2026-11-27: the firmware keeps a client's power save that was on before
# ap0 started, and refuses to turn it on afterwards, so a plain toggle cannot
# reproduce it); then "off".  The device drops off the hotspot for a few
# seconds at each restart and rejoins by itself.  In each phase the phone
# pings the device and 9.9.9.9 (20 pings, 1/s), and runs an iperf3 server
# for 15 s.  On the laptop meanwhile, in two terminals:
#
#   ping -D 10.42.0.1          # to the phone: the stream's path
#   ping -D 9.9.9.9            # through the uplink
#
# and, when the log says "iperf3 window", once per phase:
#
#   iperf3 -c 10.42.0.1 -t 10          # laptop to phone
#   iperf3 -c 10.42.0.1 -t 10 -R       # phone to laptop (the stream's direction)
#
# What confirms the power-saving cause: in the "off" phases, the phone's and
# the laptop's pings lose their 100-1000 ms spikes when idle (expected: a
# median under 20 ms to the phone, the uplink's own latency plus about 10 ms
# to 9.9.9.9), and the iperf3 rates come closer to the uplink's own.
# Unchanged rates with better pings mean the airtime (one radio, two hops on
# one channel) is the remaining limit.  To compare SCC and MCC, run it once
# with the uplink on a non-radar channel (36-48, 149-165) and once on a radar
# one (52-144), and compare the "off" phases.
PATH=/run/current-system/profile/bin:/run/current-system/profile/sbin:$PATH
log=/root/hotspot-ab.log
con=pro1x-hotspot
rounds=${1:-3}
exec > >(tee -a "$log") 2>&1
echo "=== hotspot A/B start $(date)"

[ -e /sys/class/net/ap0 ] || { echo "no ap0: start the hotspot with Keep Wi-Fi on, beside a network"; exit 1; }
[ "$(nmcli -g GENERAL.STATE connection show "$con")" = activated ] || { echo "the hotspot is not on"; exit 1; }
orig=$(iw dev wlan0 get power_save | awk '{ print $3 }')
restore() {
    # The hotspot back on if a restart failed, power saving as found (on is
    # refused while ap0 runs; off holds).
    [ "$(nmcli -g GENERAL.STATE connection show "$con")" = activated ] || nmcli connection up "$con"
    iw dev wlan0 set power_save "$orig"
    echo "restored: hotspot $(nmcli -g GENERAL.STATE connection show "$con"), wlan0 $(iw dev wlan0 get power_save)"
    echo "=== end $(date)"
}
trap restore EXIT

client=$(iw dev ap0 station dump | awk '/^Station/ { print $2; exit }')
[ -n "$client" ] || { echo "no device on the hotspot"; exit 1; }
ip=$(awk -v m="$client" '$2 == m { print $3 }' /var/lib/NetworkManager/dnsmasq-ap0.leases)
[ -n "$ip" ] || { echo "the device has no lease yet"; exit 1; }
echo "device at $ip; wlan0 power save was $orig"

# The hotspot restarted with wlan0 in power saving, and the device back on it.
restart_with_ps_on() {
    nmcli connection down "$con" > /dev/null
    iw dev wlan0 set power_save on; sleep 2
    nmcli connection up "$con" > /dev/null || { echo "the hotspot did not restart"; exit 1; }
    for i in $(seq 60); do
        iw dev ap0 station dump | grep -q "^Station $client" && break
        sleep 1
    done
    echo "  device back after about $i s; wlan0 $(iw dev wlan0 get power_save)"
}
iw dev wlan0 link | grep -E 'freq|signal|bitrate'
iw dev ap0 info | grep channel
iw dev wlan0 info | grep channel

pings() {  # pings TARGET LABEL: 20 at 1/s, the median and the worst
    ping -c 20 -i 1 -W 2 "$1" | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | sort -n |
        awk -v l="$2" '{ a[NR] = $1 } END { printf "%s: %d/20 answered, median %.1f ms, p90 %.1f ms, max %.1f ms\n", l, NR, a[int(NR / 2) + 1], a[int(NR * 0.9)], a[NR] }'
}

for r in $(seq "$rounds"); do
    for ps in on off; do
        if [ "$ps" = on ]; then restart_with_ps_on; else iw dev wlan0 set power_save off; fi
        sleep 3
        echo "--- round $r: wlan0 power save $ps ($(date +%T)); firmware: $(dmesg | grep -c 'refusing to enable ps') refusals so far"
        pings "$ip" "  phone -> device, idle"
        pings 9.9.9.9 "  phone -> 9.9.9.9, idle"
        if command -v iperf3 > /dev/null; then
            echo "  iperf3 window: 15 s, run iperf3 -c 10.42.0.1 on the device now ($(date +%T))"
            timeout 15 iperf3 -s -1 2>&1 | grep -E 'receiver|sender' | sed 's/^/  /'
        else
            echo "  no iperf3 on the phone: measure with the device's pings only"; sleep 15
        fi
        iw dev ap0 station dump | grep -E 'tx bitrate|rx bitrate|tx failed|tx retries|signal:' | sed 's/^/  ap0 /'
    done
done
