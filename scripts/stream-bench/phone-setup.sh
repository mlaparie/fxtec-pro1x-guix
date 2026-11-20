#!/bin/sh
# phone-setup.sh — put the stream test tools on the phone (after a reboot,
# which empties /tmp), from the PC:  sh scripts/stream-bench/phone-setup.sh
#
# Copies phone-clock.py with a launcher (/tmp/phone-clock: the camera
# app's environment, which has GTK), the awake logger, and the development
# server (/tmp/dev/stream.py from device/sway/pro1x-stream-webrtc, launched
# by /tmp/dev/run.sh with the installed server's environment).  Starts an
# interactive stream as the menu does, saves its server's arguments and
# environment for run.sh, then opens the test window.
set -e
here=$(dirname "$0")
repo=$here/../..
phone=${PRO1X_PHONE:-172.16.42.1}
ssh="ssh -i $HOME/.ssh/pro1x-guix -o IdentitiesOnly=yes root@$phone"
scp="scp -q -i $HOME/.ssh/pro1x-guix -o IdentitiesOnly=yes"
$ssh 'mkdir -p /tmp/dev'
$scp "$here/phone-clock.py" root@$phone:/tmp/phone-clock.py
$scp "$here/phone-run-dev.sh" root@$phone:/tmp/dev/run.sh
$scp "$here/phone-awake-watch.sh" root@$phone:/tmp/dev/awake-watch.sh
$scp "$repo/device/sway/pro1x-stream-webrtc" root@$phone:/tmp/dev/stream.py
$ssh 'set -e
w=$(readlink -f /run/current-system/profile/bin/pro1x-camera-app)
py=$(head -1 "$(grep -o "/gnu/store/[^\"]*real" "$w" | head -1)" | cut -c3-)
sed "s|^exec .*|exec $py /tmp/phone-clock.py|" "$w" > /tmp/phone-clock
w=$(readlink -f /run/current-system/profile/bin/pro1x-stream-webrtc)
sed "s|^exec .*|exec -a pro1x-stream-webrtc $py /tmp/dev/stream.py \"\$@\"|" "$w" > /tmp/dev/pro1x-stream-webrtc
chmod 755 /tmp/phone-clock /tmp/dev/run.sh /tmp/dev/awake-watch.sh /tmp/dev/pro1x-stream-webrtc
chown -R user /tmp/dev /tmp/phone-clock.py
pgrep -f "^/run/current-system/profile/bin/bash /tmp/dev/awake-watch.sh" >/dev/null ||
    setsid -f /tmp/dev/awake-watch.sh </dev/null >/dev/null 2>&1
S=$(ls /run/user/1000/sway-ipc.*.sock | head -1)
su - user -c "export SWAYSOCK=$S XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1; pro1x-stream --interactive" >/dev/null 2>&1 || true
sleep 4
p=$(cat /run/user/1000/pro1x-stream.pid)
cp /proc/$p/cmdline /tmp/dev/cmdline
cp /proc/$p/environ /tmp/dev/environ
chown user /tmp/dev/cmdline /tmp/dev/environ
su user -s /bin/sh -c "swaymsg -s $S exec \"/tmp/phone-clock > /tmp/phone-clock.log 2>&1\"" >/dev/null
cat /run/user/1000/pro1x-stream.to'
