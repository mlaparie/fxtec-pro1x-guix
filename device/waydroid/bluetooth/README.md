# Waydroid Bluetooth: the prebuilt soft HCI HAL

`android.hardware.bluetooth@1.0-service.waydroid` is waydroid-host-stack's
soft HCI HAL (MIT, github.com/isyourbrainfoss/waydroid-host-stack, commit
d9a316e, `guest/hal/`), built for Android 13 arm64 by its
`guest/hal/build_ndk.sh` with the Android NDK r28c, against AOSP's VNDK v33
headers and the libraries of Waydroid's LineageOS 20 image (TQ3A.230901.001).
It is prebuilt because Guix cannot run the NDK, and the build needs Android's
own libc++.  sha256 1ef8bfd3e40f7ada906413f2ed9268a6c12679cba8708209f13034f9eb92aaa3.

To rebuild (2026-11-18, on an x86_64 Guix host):

    guix shell -CF --emulate-fhs --share=$PWD bash coreutils sed grep \
      gcc-toolchain zlib -- env -u CPLUS_INCLUDE_PATH -u C_INCLUDE_PATH \
      -u LIBRARY_PATH -u CPATH ANDROID_NDK_HOME=$PWD/android-ndk-r28c \
      HAL_DEPS=$PWD/hal-deps HAL_BUILD_DIR=$PWD/hal-out \
      bash waydroid-host-stack/guest/hal/build_ndk.sh

with `hal-deps` as `guest/hal/fetch-hal-deps.sh` describes (the seven
libraries taken from Waydroid's `system.img` with debugfs).

The two XML files are the permission and feature files that
waydroid-host-stack's `waydroid-restore-bluetooth-apk.sh` writes.
