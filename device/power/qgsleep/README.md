# qgsleep: the battery current during system sleep

A debug module from moWerk's SailfishOS port of the Pro¹x
(github.com/moWerk/sailfishos-pro1x-mainline, `tools/qgsleep/`, GPL-2.0),
copied unchanged on 2026-11-07.

The PMI632 fuel gauge (QG) keeps sampling the battery while the SoC sleeps.
At suspend the module clears and restarts the QG's FIFO; at resume it prints
the FIFO's mean current, which is the mean battery current of that sleep:

    insmod pro1x-qgsleep's qgsleep.ko
    (suspend from the power menu, unplugged; wake it after a few minutes)
    dmesg | grep qgsleep   # "qgsleep slept N ms: ... mean -NNNNN uA"

It reads named QG registers only and toggles the FIFO hold bit, as the
downstream driver does; moWerk found that reading whole PMIC register maps
through debugfs crashed the phone, so do not.  Awake on USB, the FIFO stays
empty.  moWerk's results with it: `notes/sleep.md` in his repository.

State: build-tested only.
