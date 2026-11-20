#!/usr/bin/env python3
"""phone-clock.py: a full-screen test window for measuring the stream.

Runs on the phone, in the Sway session.  Each display frame shows the
phone's clock (milliseconds, modulo 2^24) as a row of 24 blocks, with the
same bits inverted below so that a reader can tell a clean frame from a
blurred one; stream-bench.py decodes them on the PC from the stream page's
canvas, and the server (PRO1X_STREAM_BENCH=1) from its frames.  A square
in the middle changes on each key press, to time a key's way to the phone
and back.  A bar sweeps along the bottom, so the picture always moves.

The Pro1x has an OLED panel, which a still picture marks for good: the
background is black (pixels off), the blocks dim grey, and every block
and the square change each second (all inverted every other second; a
25th block says which), so no pixel stays lit.

The time drawn is when the frame is drawn; it reaches the panel at the
next refresh (up to 17 ms later), so measured ages are a little high.
"""
import time

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

BITS = 24
LIT = 0.55
presses = 0
drawn = [0, time.monotonic()]


def draw(area, cr):
    w, h = area.get_allocated_width(), area.get_allocated_height()
    now = time.time_ns() // 1_000_000
    drawn[0] += 1
    if time.monotonic() - drawn[1] >= 5:
        print(f"{drawn[0] / (time.monotonic() - drawn[1]):.1f} frames/s drawn",
              flush=True)
        drawn[:] = [0, time.monotonic()]
    phase = (now // 1000) % 2
    value = now % (1 << BITS)
    cr.set_source_rgb(0, 0, 0)
    cr.paint()
    cell = w * 0.96 / (BITS + 1)
    for i in range(BITS + 1):
        bit = phase if i == BITS else ((value >> (BITS - 1 - i)) & 1) ^ phase
        x = w * 0.02 + i * cell
        for top, on in ((0.10, bit), (0.25, 1 - bit)):
            cr.set_source_rgb(LIT * on, LIT * on, LIT * on)
            cr.rectangle(x, h * top, cell, h * 0.15)
            cr.fill()
    on = (presses % 2) ^ phase
    cr.set_source_rgb(LIT * on, LIT * on, LIT * on)
    cr.rectangle(w * 0.40, h * 0.55, w * 0.20, h * 0.30)
    cr.fill()
    cr.set_source_rgb(0.4, 0.1, 0.05)
    cr.rectangle((now % 2000) / 2000 * w * 0.95, h * 0.90, w * 0.05, h * 0.10)
    cr.fill()


def key(_window, _event):
    global presses
    presses += 1


def tick(widget, _clock):
    """Only the blocks, the square and the bar are drawn again: a full
    screen in software each frame held the window to about 10 frames/s."""
    w, h = widget.get_allocated_width(), widget.get_allocated_height()
    widget.queue_draw_area(0, int(h * 0.10), w, int(h * 0.30) + 1)
    widget.queue_draw_area(int(w * 0.40), int(h * 0.55), int(w * 0.20) + 1, int(h * 0.30) + 1)
    widget.queue_draw_area(0, int(h * 0.90), w, h - int(h * 0.90))
    return True


window = Gtk.Window(title="stream-bench clock")
area = Gtk.DrawingArea()
area.connect("draw", draw)
area.add_tick_callback(tick)
window.add(area)
window.connect("key-press-event", key)
window.connect("destroy", Gtk.main_quit)
window.fullscreen()
window.show_all()
Gtk.main()
