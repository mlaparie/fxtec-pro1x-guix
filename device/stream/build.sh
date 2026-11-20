#!/bin/sh
# build.sh — build pro1x-screencast where its dependencies are (a Guix
# shell, or the package's build): wayland-scanner makes the protocol code.
set -e
cd "$(dirname "$0")"
wl=$(pkg-config --variable=pkgdatadir wayland-protocols)
wlr=$(pkg-config --variable=pkgdatadir wlr-protocols)
for x in "$wl/stable/linux-dmabuf/linux-dmabuf-v1.xml" \
         "$wlr/unstable/wlr-screencopy-unstable-v1.xml"; do
    n=$(basename "$x" .xml)
    wayland-scanner client-header "$x" "$n-client-protocol.h"
    wayland-scanner private-code "$x" "$n-protocol.c"
done
${CC:-gcc} -O2 -Wall -Wextra -I. -o pro1x-screencast pro1x-screencast.c \
    linux-dmabuf-v1-protocol.c wlr-screencopy-unstable-v1-protocol.c \
    $(pkg-config --cflags --libs wayland-client gbm egl glesv2 libdrm)
