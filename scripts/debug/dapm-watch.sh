#!/run/current-system/profile/bin/bash
# dapm-watch.sh — on the phone, as root: print the power state of the speaker
# amplifiers, HPH/EAR stages and card bias, and the state of every PCM, each
# time one changes (10 ms polling; the kernel has no tracefs).  Used to find
# the login pops (rag-notes/hardware.json, audio).
cd "/sys/kernel/debug/asoc/F(x)tec Pro1X" || exit 1
W=("aw87339.1-0059/dapm/Spk0 SPK PA" "aw87339.1-005a/dapm/Spk1 SPK PA"
   "audio-codec/dapm/HPHL PGA" "audio-codec/dapm/HPHR PGA" "audio-codec/dapm/EAR PGA"
   "audio-codec/dapm/VDD_BUCK" "audio-codec/dapm/CLS_H_PORT" "audio-codec/dapm/bias_level"
   "dapm/bias_level")
prev=""
while :; do
  cur=""
  for w in "${W[@]}"; do read -r l < "$w"; l=${l#*: }; cur+="${w##*/}=${l%% *};"; done
  for p in /proc/asound/card0/pcm*/sub0/status; do read -r s < "$p"; n=${p#/proc/asound/card0/}; cur+="${n%%/*}=${s%% *};"; done
  if [ "$cur" != "$prev" ]; then echo "$EPOCHREALTIME $cur"; prev=$cur; fi
  sleep 0.01
done
