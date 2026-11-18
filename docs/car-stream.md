# Car stream: the Pro¹x's screen in a car's browser (plan)

State: a plan, nothing built (2026-11-18).  Branch `streaming`.

## Goal

The car's browser opens a URL served by the Pro¹x and shows a screen of
the Pro¹x, with its sound, and sends back touches, gestures and keys.  It
is for music apps, turn-by-turn navigation, and the Sway desktop with its
terminal apps (mail, monitoring), and it keeps streaming while driving, as
the author's Android app Tesor does on a Tesla.

Targets:

- video delay from the Pro¹x to the car of about 100-150 ms;
- sound in step with the picture, at most 400 ms apart, with a resync
  button;
- touches, multi-finger gestures and the car's keyboard working on the
  Pro¹x;
- the Pro¹x's hotspot as the network (the car joins it).  Hotspot and
  Wi-Fi client at the same time: later.

## What exists, and why it is not enough

- `device/sway/pro1x-stream` (the Stream menu): wf-recorder copies an area
  of the display and pipes it to an encoder or a server.  The pipe between
  two processes buffers frames, which adds delay.
- `device/sway/pro1x-stream-webrtc`: WebRTC by GStreamer's `webrtcbin`,
  offer and answer over plain HTTP, H.264 (hardware, from raw NV12) or VP8
  (software).  VP8 played in a browser (author, 2026-11-10); the hardware
  path not yet seen in a browser.  No sound, no input, the picture in a
  `<video>` element.

The car stream reuses the WebRTC part (no signalling server, local ICE
only) and replaces the rest.

## Design

1. **A screen of its own.**  A Sway headless output (`swaymsg
   create_output`) at the car's viewport size, which the page reports at
   its first request, with its own workspace.  The Pro¹x keeps its own
   screen (or turns it off) while the car shows another one.  Mirroring
   the Pro¹x's screen stays an option.
2. **Capture in the same process as the encoder.**  `pipewiresrc` fed by
   xdg-desktop-portal-wlr's ScreenCast (already the portal here), with its
   chooser set to pick the headless output without asking; or, if the
   portal adds delay, a small wlr-screencopy source using dma-bufs.  Frames
   only when something changed: a still terminal costs almost nothing.
3. **Hardware H.264.**  `v4l2h264enc` (Venus, the camera app's recorder):
   no B-frames, a short GOP, a capped bitrate, a keyframe when the viewer
   asks (`keep_keyframes` exists).  Fallback: x264 `ultrafast zerolatency`.
4. **Sound.**  A PipeWire sink "Car" that music and navigation apps go to
   (or the monitor of the default sink), `pipewiresrc` → `opusenc` (10-20 ms
   frames) → RTP, in the same `webrtcbin` session as the video, on the
   same clock, so RTCP sender reports keep the two in step.  Resync button:
   the page sets the receivers' `jitterBufferTarget` low again and the
   Pro¹x restarts the sound branch.
5. **Transport.**  `webrtcbin latency=0`, the page's receivers with the
   lowest jitter buffer target, ICE with the hotspot's address only.  The
   author reports that the Tesla browser accepts WebRTC (to confirm, M0).
6. **Showing it in the car.**  The decoded frames drawn on a `<canvas>`
   (from a hidden `<video>` with `requestVideoFrameCallback`), or decoded
   by WebCodecs from frames sent over the data channel, which also skips
   the jitter buffer.  Which one keeps playing while driving, and which has
   the lower delay, is measured in M0 and M4.  Sound by `<audio>` or Web
   Audio.
7. **Input.**  A WebRTC data channel in the same connection: pointer and
   touch events (unordered, for moves) and keys (ordered).  On the Pro¹x,
   a uinput touchscreen mapped to the headless output (`swaymsg input …
   map_to_output`) and a uinput keyboard, so Sway and the apps see real
   touches and gestures.  Needs `/dev/uinput` for the session user (a udev
   rule).  The car's keyboard comes up through a hidden text field; its
   text arrives as key events, or as text when it composes.
8. **Network.**  The existing NetworkManager hotspot, or the VPN; the car
   opens `http://<address>:<port>/<token>`.  The phone's mobile data can
   be shared with the car (author's decision each time: it is the SIM's
   data).
9. **Running.**  A "Car stream" line in quick actions, also offered in the
   Hotspot and VPN menus, which start it on that network's address; no
   config.scm option (author).  Suspend inhibited while a viewer is
   connected; the Pro¹x's own screen may go off.
10. **Safety of the desktop.**  Input is full control of the session: the
    server binds to the chosen interface only (hotspot or VPN), the URL carries a random
    token, the hotspot uses WPA2.

## Milestones

- **M0, in the car (author):** the existing `pro1x-stream-webrtc` page in
  the Tesla browser over the hotspot: H.264 or only VP8; `<video>` and
  `<canvas>` while parked and while driving; the viewport size; which touch
  and pointer events arrive; whether the on-screen keyboard opens.
- **M1:** headless output, capture, hardware encoding in one process;
  delay measured against a PC browser (a clock on the Pro¹x, both screens
  in one photo); CPU and battery current.
- **M2:** sound, sync, resync button; offset measured with a flash-and-beep
  page.
- **M3:** input over the data channel, uinput touch and keyboard.
- **M4:** the car page: canvas or WebCodecs, full screen, reconnect after
  the car sleeps, the token.
- **M5:** the quick actions line, and the entries in the Hotspot and VPN
  menus; docs.
- **Later:** hotspot and Wi-Fi client at once (ath10k's interface
  combinations decide it).

## Open questions

- The car: model, browser version, viewport size.
- Does the encoder keep 30 fps at the car's size with the Pro¹x's own
  screen still on?
- Does Sway keep drawing a headless output while the Pro¹x's screen is off?
