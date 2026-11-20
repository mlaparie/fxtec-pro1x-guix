#!/run/current-system/profile/bin/bash
# Logs each change of Keep screen on, swayidle, the panel's power and the
# lock screen to /tmp/dev/awake.log (with the parents of a new swayidle);
# turns the panel back on when it goes off while Keep screen on is set.
S=$(ls /run/user/1000/sway-ipc.*.sock | head -1)
sw() { su user -s /bin/sh -c "SWAYSOCK=$S swaymsg $*"; }
last=
while sleep 2; do
    caf=$(cat /run/user/1000/pro1x-caffeine 2>/dev/null)
    idle=$(pgrep -x swayidle | tr '\n' ' ')
    power=$(sw -t get_outputs -r 2>/dev/null | grep -o '"power": [a-z]*' | head -1 | cut -d' ' -f2)
    lock=$(pgrep -x gtklock)
    now="caffeine=$caf swayidle=[$idle] power=$power gtklock=[$lock]"
    if [ "$now" != "$last" ]; then
        echo "$(date +%H:%M:%S) $now" >> /tmp/dev/awake.log
        for p in $idle; do
            echo "   swayidle $p: $(tr '\0' ' ' < /proc/$p/cmdline | cut -c1-200)" >> /tmp/dev/awake.log
            pp=$(awk '{print $4}' /proc/$p/stat); echo "   parent $pp: $(tr '\0' ' ' < /proc/$pp/cmdline | cut -c1-200)" >> /tmp/dev/awake.log
        done
        last=$now
    fi
    if [ "$caf" = on ] && [ "$power" = false ]; then
        echo "$(date +%H:%M:%S) panel off with Keep screen on: turned on again" >> /tmp/dev/awake.log
        sw "'output * power on'" >/dev/null
        sw "'input type:touch events enabled'" >/dev/null
    fi
done
