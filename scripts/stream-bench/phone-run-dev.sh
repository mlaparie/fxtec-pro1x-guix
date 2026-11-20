#!/run/current-system/profile/bin/bash
# (Test tool: restarts are what hung the phone twice, 2026-11-20; space them out.)
# Restart the stream server from /tmp/dev/stream.py with the saved
# arguments and environment of the installed one, as user, with the
# per-stage delays logged.  Extra NAME=value arguments go to its environment.
p=$(cat /run/user/1000/pro1x-stream.pid 2>/dev/null)
[ -n "$p" ] && kill "$p" 2>/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$p" 2>/dev/null || break; sleep 0.5; done
# Its ports free (it can take a few seconds more to let them go).
for _ in $(seq 20); do ss -ltn | grep -qE ':(8443|8081) ' || break; sleep 0.5; done
mapfile -d '' args < /tmp/dev/cmdline
mapfile -d '' envs < /tmp/dev/environ
cd /tmp/dev
su user -s /run/current-system/profile/bin/bash -c '
    exec setsid env -i "$@" >/tmp/dev/server.out 2>&1 </dev/null' -- \
    "${envs[@]}" PRO1X_STREAM_BENCH=1 "$@" /tmp/dev/pro1x-stream-webrtc "${args[@]:2}" &
sleep 3
pgrep -n -f "^pro1x-stream-webrtc /tmp/dev/stream.py" > /run/user/1000/pro1x-stream.pid
echo "server $(cat /run/user/1000/pro1x-stream.pid)"
