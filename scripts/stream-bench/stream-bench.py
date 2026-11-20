#!/usr/bin/env python3
"""stream-bench.py: measure the interactive stream from a browser on the PC.

    guix shell python python-websocket-client -- \\
        python3 scripts/stream-bench/stream-bench.py URL|auto [SECONDS] [LABEL]

Needs Chromium started with --remote-debugging-port=9222, the phone on
USB (172.16.42.1, root's key ~/.ssh/pro1x-guix) and phone-clock.py full
screen on the streamed output.  It:
- measures the offset between the phone's clock and this one over SSH
  (the reply with the shortest round trip, so a millisecond or two);
- opens URL in Chromium (or reuses the tab already on it) and adds a
  reader to the page, which decodes the clock blocks of the stream's
  canvas at each display refresh: a frame's age is this PC's time, in the
  phone's clock, less the time the phone drew on it;
- presses a key in the page every 2 s and times the square's flip: the
  key's way to the phone and the picture's way back, as typing feels;
- prints the ages (median, 95th percentile, worst), their spread, frames
  shown per second, the longest gap between new frames, and key times;
  one JSON line per run is appended to stream-bench.jsonl beside it.
"""
import json
import os
import statistics
import subprocess
import sys
import time
import urllib.request

import websocket

PHONE = ["ssh", "-i", os.path.expanduser("~/.ssh/pro1x-guix"),
         "-o", "IdentitiesOnly=yes",
         "root@" + os.environ.get("PRO1X_PHONE", "172.16.42.1")]
CDP = "http://127.0.0.1:9222"
HERE = os.path.dirname(os.path.abspath(__file__))

READER = r"""
(() => {
  if (window.__bench) { window.__bench.reset(); return "reset"; }
  const B = window.__bench = {ages: [], shown: [], keys: [], last: -1,
                              ind: null, keyAt: null, offset: 0, bad: 0};
  B.reset = () => { B.ages = []; B.shown = []; B.keys = []; B.bad = 0; };
  addEventListener("keydown", () => { B.keyAt = performance.now(); }, true);
  const loop = () => {
    const c = document.getElementById("c");
    if (c && c.width > 16 && c.style.display !== "none") {
      const g = c.getContext("2d"), W = c.width, H = c.height;
      const A = g.getImageData(0, Math.floor(H * 0.175), W, 1).data;
      const R = g.getImageData(0, Math.floor(H * 0.325), W, 1).data;
      // 25 blocks: 24 bits, then the phase that inverts them all every
      // other second (the panel is OLED: no pixel stays lit).
      let v = 0, ok = true, phase = 0;
      for (let i = 0; i < 25; i++) {
        const x = Math.floor(W * (0.02 + 0.96 * (i + 0.5) / 25)) * 4 + 1;
        if (Math.abs(A[x] - R[x]) < 60) { ok = false; break; }
        if (i < 24) v = v * 2 + (A[x] > R[x] ? 1 : 0);
        else phase = A[x] > R[x] ? 1 : 0;
      }
      if (phase) v ^= 0xffffff;
      const now = performance.now();
      if (!ok) B.bad++;
      else if (v !== B.last) {
        let d = ((Date.now() + B.offset) % 16777216) - v;
        if (d < -8388608) d += 16777216;
        B.ages.push(d); B.shown.push(now); B.last = v;
      }
      if (!ok) { requestAnimationFrame(loop); return; }
      const s = (g.getImageData(Math.floor(W * 0.5), Math.floor(H * 0.7), 1, 1).data[1] > 70) !== !!phase;
      if (B.ind === null) B.ind = s;
      if (s !== B.ind) {
        B.ind = s;
        if (B.keyAt !== null) { B.keys.push(now - B.keyAt); B.keyAt = null; }
      }
    }
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
  return "added";
})()
"""


def clock_offset():
    """The phone's clock less this one's, in ms."""
    p = subprocess.Popen(
        # The system has no python3 of its own: the one the clock's
        # launcher runs (/tmp/phone-clock, see README).
        PHONE + ["$(sed -n 's/^exec \\([^ ]*\\) .*/\\1/p' /tmp/phone-clock)"
                 " -u -c 'import sys,time\n"
                 "for _ in sys.stdin: print(time.time_ns()//1000)'"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    best = None
    for _ in range(40):
        t0 = time.time_ns() / 1000
        p.stdin.write("\n"); p.stdin.flush()
        phone = int(p.stdout.readline())
        t1 = time.time_ns() / 1000
        if best is None or t1 - t0 < best[0]:
            best = (t1 - t0, phone - (t0 + t1) / 2)
    p.stdin.close(); p.wait()
    return best[1] / 1000, best[0] / 1000


class Tab:
    def __init__(self, url):
        tabs = json.load(urllib.request.urlopen(CDP + "/json"))
        page = next((t for t in tabs if t["type"] == "page"
                     and t["url"].split("?")[0] == url.split("?")[0]), None)
        if page is None:
            page = next(t for t in tabs if t["type"] == "page")
            self.ws = websocket.create_connection(page["webSocketDebuggerUrl"], suppress_origin=True)
            self.n = 0
            # The phone's own certificate, on its address: this test
            # profile only, for this connection only (set again each run).
            self.call("Security.setIgnoreCertificateErrors", ignore=True)
            self.call("Page.navigate", url=url)
            time.sleep(8)
        else:
            # Loaded again for each run: a server started again needs a
            # new page, and each run starts from the same state.
            self.ws = websocket.create_connection(page["webSocketDebuggerUrl"], suppress_origin=True)
            self.n = 0
            self.call("Security.setIgnoreCertificateErrors", ignore=True)
            self.call("Page.reload", ignoreCache=True)
            time.sleep(8)

    def call(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            m = json.loads(self.ws.recv())
            if m.get("id") == self.n:
                return m.get("result", {})

    def eval(self, expr):
        r = self.call("Runtime.evaluate", expression=expr, returnByValue=True)
        return r.get("result", {}).get("value")

    def key(self, ch="a"):
        for kind in ("keyDown", "keyUp"):
            self.call("Input.dispatchKeyEvent", type=kind, key=ch, text=ch,
                      code="Key" + ch.upper(), windowsVirtualKeyCode=ord(ch.upper()))


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * p))] if xs else None


def main():
    url = sys.argv[1]
    if url == "auto":
        # The address the menu shows (it changes with the phone's lease),
        # with the stream's key.
        to = subprocess.run(PHONE + ["cat /run/user/1000/pro1x-stream.to"],
                            capture_output=True, text=True).stdout.split()
        key = to[to.index("key") + 1] if "key" in to else ""
        url = to[1].rstrip(",") + (f"?k={key}" if key else "")
    seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    label = sys.argv[3] if len(sys.argv) > 3 else ""
    offset, rtt = clock_offset()
    tab = Tab(url)
    loaded = time.time()
    tab.eval(READER)
    tab.eval(f"window.__bench.offset = {offset:.1f}; window.__bench.reset()")
    # From the reload to the first frame read: what a viewer waits.
    while not tab.eval("__bench.ages.length") and time.time() - loaded < 30:
        time.sleep(0.2)
    first = round(time.time() - loaded + 8, 1)
    tab.eval("window.__bench.reset()")
    end = time.time() + seconds
    offsets = [offset]
    n = 0
    while time.time() < end:
        time.sleep(2)
        tab.key()
        n += 1
        # The phone's clock moves while NTP corrects it (230 ms in 4 min
        # after a boot, 2026-11-20): measured again every 10 s.
        if n % 5 == 0:
            offsets.append(clock_offset()[0])
            tab.eval(f"window.__bench.offset = {offsets[-1]:.1f}")
    b = tab.eval("({ages: __bench.ages, shown: __bench.shown, keys: __bench.keys,"
                 " bad: __bench.bad})")
    ages, shown, keys = b["ages"], b["shown"], b["keys"]
    gaps = [b2 - a for a, b2 in zip(shown, shown[1:])]
    span = (shown[-1] - shown[0]) / 1000 if len(shown) > 1 else 0
    r = {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "label": label,
         "seconds": seconds, "offset_ms": round(offset, 1),
         "offset_rtt_ms": round(rtt, 1),
         "offset_moved_ms": round(max(offsets) - min(offsets), 1), "frames": len(ages),
         "fps": round(len(ages) / span, 1) if span else 0,
         "age_p50": pct(ages, 0.5), "age_p95": pct(ages, 0.95),
         "age_max": max(ages) if ages else None,
         "age_sd": round(statistics.pstdev(ages), 1) if len(ages) > 1 else None,
         "gap_p95": round(pct(gaps, 0.95), 1) if gaps else None,
         "gap_max": round(max(gaps), 1) if gaps else None,
         "key_p50": round(pct(keys, 0.5), 1) if keys else None,
         "key_max": round(max(keys), 1) if keys else None,
         "keys": f"{len(keys)}/{seconds // 2}", "unreadable": b["bad"],
         "first_frame_s": first}
    print(json.dumps(r))
    with open(os.path.join(HERE, "stream-bench.jsonl"), "a") as f:
        f.write(json.dumps(r) + "\n")


if __name__ == "__main__":
    main()
