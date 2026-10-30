// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * pro1x-doubletap — wake the panel with a double tap on the touchscreen.
 *
 * The Goodix touchscreen keeps reporting touches while the panel is off
 * (measured on the Pro1X, 2026-10-30), so a double tap can be detected in
 * userspace, as SailfishOS's mce does.  While the DSI connector's dpms is
 * "Off", two touch-downs less than INTERVAL_MS apart and within DISTANCE
 * touchscreen units of each other send a power-key press from a uinput
 * device; Phosh, Sway (XF86PowerOff) and Sxmo all wake on it.  Esc on the
 * hardware keyboard does the same while the panel is off (read from keyd's
 * virtual keyboard, since keyd grabs the real one).  Nothing happens while
 * the panel is on.
 *
 * Usage: pro1x-doubletap [interval-ms [distance]]   (defaults 400, 150)
 *
 * State: double tap tested on the phone (author, 2026-10-30); Esc written
 * 2026-10-30, not yet run.
 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define TOUCH_NAME "Goodix Capacitive TouchScreen"
#define KEYBOARD_NAME "keyd virtual keyboard"

static long interval_ms = 400;
static long distance = 150;

static long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* "On" or "Off" in /sys/class/drm/<connector>/dpms for the DSI panel.
 * A cached kernel value: reading it does not touch the DSI link. */
static int panel_off(void)
{
	DIR *d = opendir("/sys/class/drm");
	struct dirent *e;
	int off = 0;

	if (!d)
		return 0;
	while ((e = readdir(d))) {
		char path[512], buf[8] = "";
		FILE *f;

		if (!strstr(e->d_name, "-DSI-"))
			continue;
		snprintf(path, sizeof path, "/sys/class/drm/%s/dpms", e->d_name);
		f = fopen(path, "r");
		if (!f)
			continue;
		if (fgets(buf, sizeof buf, f) && !strncmp(buf, "Off", 3))
			off = 1;
		fclose(f);
	}
	closedir(d);
	return off;
}

static int open_named(const char *want)
{
	for (int i = 0; i < 32; i++) {
		char path[64], name[256] = "";
		int fd;

		snprintf(path, sizeof path, "/dev/input/event%d", i);
		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		if (ioctl(fd, EVIOCGNAME(sizeof name), name) >= 0 &&
		    !strcmp(name, want))
			return fd;
		close(fd);
	}
	return -1;
}

static int open_uinput(void)
{
	struct uinput_setup setup = { .id = { .bustype = BUS_VIRTUAL } };
	int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);

	if (fd < 0)
		return -1;
	ioctl(fd, UI_SET_EVBIT, EV_KEY);
	ioctl(fd, UI_SET_KEYBIT, KEY_POWER);
	strcpy(setup.name, "pro1x-doubletap");
	if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

static void emit(int fd, int type, int code, int value)
{
	struct input_event ev = { .type = type, .code = code, .value = value };

	if (write(fd, &ev, sizeof ev) < 0)
		perror("uinput write");
}

static void press_power(int fd)
{
	emit(fd, EV_KEY, KEY_POWER, 1);
	emit(fd, EV_SYN, SYN_REPORT, 0);
	emit(fd, EV_KEY, KEY_POWER, 0);
	emit(fd, EV_SYN, SYN_REPORT, 0);
}

int main(int argc, char **argv)
{
	int touch, out, x = 0, y = 0;
	long last_down = 0, quiet_until = 0;
	int last_x = 0, last_y = 0;

	if (argc > 1)
		interval_ms = atol(argv[1]);
	if (argc > 2)
		distance = atol(argv[2]);

	touch = open_named(TOUCH_NAME);
	if (touch < 0) {
		fprintf(stderr, "pro1x-doubletap: no \"%s\" device\n", TOUCH_NAME);
		return 1;
	}
	out = open_uinput();
	if (out < 0) {
		perror("pro1x-doubletap: /dev/uinput");
		return 1;
	}
	fprintf(stderr, "pro1x-doubletap: watching, interval %ld ms, distance %ld\n",
		interval_ms, distance);

	int kbd = open_named(KEYBOARD_NAME);	/* -1 until keyd made it */

	for (;;) {
		struct pollfd p[2] = {
			{ .fd = touch, .events = POLLIN },
			{ .fd = kbd, .events = POLLIN },
		};
		struct input_event ev;

		if (poll(p, kbd >= 0 ? 2 : 1, kbd >= 0 ? -1 : 5000) < 0) {
			if (errno == EINTR)
				continue;
			perror("poll");
			return 1;
		}
		if (p[0].revents & (POLLERR | POLLHUP)) {
			fprintf(stderr, "pro1x-doubletap: touch device gone\n");
			return 1;	/* Shepherd respawns us */
		}
		if (kbd < 0) {
			kbd = open_named(KEYBOARD_NAME);
		} else if (p[1].revents & (POLLERR | POLLHUP)) {
			close(kbd);	/* keyd restarted: reopen later */
			kbd = -1;
		} else if (p[1].revents & POLLIN) {
			while (read(kbd, &ev, sizeof ev) == sizeof ev) {
				long t = now_ms();

				if (ev.type == EV_KEY && ev.code == KEY_ESC &&
				    ev.value == 1 && t >= quiet_until && panel_off()) {
					press_power(out);
					fprintf(stderr, "pro1x-doubletap: Esc, power key sent\n");
					quiet_until = t + 1500;
				}
			}
		}
		if (!(p[0].revents & POLLIN))
			continue;
		while (read(touch, &ev, sizeof ev) == sizeof ev) {
			long t;

			if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_X)
				x = ev.value;
			else if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_Y)
				y = ev.value;
			if (!(ev.type == EV_KEY && ev.code == BTN_TOUCH && ev.value == 1))
				continue;

			/* A touch-down.  Position events of this touch may follow in
			 * the same frame; the previous ones are close enough. */
			t = now_ms();
			if (t < quiet_until || !panel_off()) {
				last_down = 0;
				continue;
			}
			if (last_down && t - last_down < interval_ms &&
			    abs(x - last_x) < distance && abs(y - last_y) < distance) {
				press_power(out);
				fprintf(stderr, "pro1x-doubletap: double tap, power key sent\n");
				last_down = 0;
				quiet_until = t + 1500;
			} else {
				last_down = t;
				last_x = x;
				last_y = y;
			}
		}
	}
}
