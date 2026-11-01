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
 * the panel is on, nor in a pocket: while /run/pro1x-pocket exists (the
 * proximity sensor sees something near, kept by pro1x-pocket; author,
 * 2026-10-30) — except on a lock screen, where a double tap away from its
 * keyboard sends the power key too, which blanks the panel (author,
 * 2026-10-31).
 *
 * Usage: pro1x-doubletap [interval-ms [distance]]   (defaults 400, 150)
 *
 * State: double tap tested on the phone (author, 2026-10-30); Esc written
 * 2026-10-30, not yet run.
 */

#include <dirent.h>
#include <errno.h>
#include <glob.h>
#include <grp.h>
#include <sys/stat.h>
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

/* In a pocket (the proximity sensor sees something near): no waking.
 * /run/pro1x-pocket is kept by pro1x-pocket (pro1x-hardware-service-type). */
static int pocketed(void)
{
	return access("/run/pro1x-pocket", F_OK) == 0;
}

/* A lock screen runs: a gtklock or swaylock process. */
static int locker_running(void)
{
	DIR *d = opendir("/proc");
	struct dirent *e;
	int found = 0;

	if (!d)
		return 0;
	while (!found && (e = readdir(d))) {
		char path[300], comm[32] = "";
		FILE *f;

		if (e->d_name[0] < '0' || e->d_name[0] > '9')
			continue;
		snprintf(path, sizeof path, "/proc/%s/comm", e->d_name);
		if (!(f = fopen(path, "r")))
			continue;
		if (fgets(comm, sizeof comm, f))
			found = !strncmp(comm, "gtklock\n", 8) || !strncmp(comm, "swaylock\n", 9);
		fclose(f);
	}
	closedir(d);
	return found;
}

/* On a lock screen, may a double tap at touch row Y blank the panel?  Not
 * over the lock screen's keyboard, where a doubled letter looks like a
 * double tap: pro1x-lock writes /run/user/UID/pro1x-lock-osk, "none" (no
 * keyboard: anywhere), "portrait" (keyboard in the lower half: upper half
 * only), or "landscape" (not mapped: never). */
static int lock_tap_allowed(int y, int ymax)
{
	glob_t g;
	char mode[16] = "none";

	if (glob("/run/user/*/pro1x-lock-osk", 0, NULL, &g) == 0) {
		FILE *f = fopen(g.gl_pathv[0], "r");

		if (f) {
			if (!fgets(mode, sizeof mode, f))
				strcpy(mode, "none");
			fclose(f);
		}
		globfree(&g);
	}
	if (!strncmp(mode, "none", 4))
		return 1;
	if (!strncmp(mode, "portrait", 8))
		return ymax > 0 && y < ymax / 2;
	return 0;
}

/* The last touch, for the camera button's clicks (pro1x-camera-button,
 * author 2026-11-01): /run/pro1x-touch holds "X Y XMAX YMAX DOWN" in
 * touchscreen units, written at each frame with a touch and at its end.
 * Through a temporary file, so a reader never sees half a line. */
static void note_touch(int x, int y, int xmax, int ymax, int down)
{
	FILE *f = fopen("/run/pro1x-touch.new", "w");

	if (!f)
		return;
	fprintf(f, "%d %d %d %d %d\n", x, y, xmax, ymax, down);
	fclose(f);
	rename("/run/pro1x-touch.new", "/run/pro1x-touch");
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
	ioctl(fd, UI_SET_KEYBIT, KEY_LEFTMETA);	/* Super, for window drags */
	strcpy(setup.name, "pro1x-doubletap");
	if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

/* The camera button's pointer (pro1x-camera-button, author 2026-11-01):
 * an absolute pointer whose position is the touch's own, in the same
 * device units scaled to 0..65535.  Mapped to DSI-1 (pro1x.conf), wlroots
 * turns it with the output exactly as it turns touches, so it lands under
 * the finger at any rotation.  Driven through the /run/pro1x-pointer fifo
 * (the input group may write): "rclick" clicks the right button at the
 * last touch; "drag" holds Super and the left button there and follows
 * the finger (Sway's floating_modifier: moves windows); "end" lets go. */
#define POINTER_FIFO "/run/pro1x-pointer"
#define POINTER_VENDOR 0x1234
#define POINTER_PRODUCT 0x5678

static int open_pointer(void)
{
	struct uinput_setup setup = { .id = { .bustype = BUS_VIRTUAL,
		.vendor = POINTER_VENDOR, .product = POINTER_PRODUCT } };
	struct uinput_abs_setup abs = { .absinfo = { .maximum = 65535 } };
	int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);

	if (fd < 0)
		return -1;
	ioctl(fd, UI_SET_EVBIT, EV_KEY);
	ioctl(fd, UI_SET_KEYBIT, BTN_LEFT);
	ioctl(fd, UI_SET_KEYBIT, BTN_RIGHT);
	ioctl(fd, UI_SET_EVBIT, EV_ABS);
	ioctl(fd, UI_SET_ABSBIT, ABS_X);
	ioctl(fd, UI_SET_ABSBIT, ABS_Y);
	abs.code = ABS_X;
	ioctl(fd, UI_ABS_SETUP, &abs);
	abs.code = ABS_Y;
	ioctl(fd, UI_ABS_SETUP, &abs);
	strcpy(setup.name, "pro1x-pointer");
	if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

/* The fifo, read end; a write end of our own so it never reads EOF. */
static int open_pointer_fifo(void)
{
	struct group *input = getgrnam("input");
	int fd;

	unlink(POINTER_FIFO);
	if (mkfifo(POINTER_FIFO, 0620) < 0)
		return -1;
	chmod(POINTER_FIFO, 0620);	/* mkfifo's mode went through the umask */
	if (input)
		chown(POINTER_FIFO, 0, input->gr_gid);
	fd = open(POINTER_FIFO, O_RDONLY | O_NONBLOCK);
	if (fd >= 0)
		open(POINTER_FIFO, O_WRONLY | O_NONBLOCK);
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

static void pointer_to(int fd, int x, int y, int xmax, int ymax)
{
	if (fd < 0 || xmax <= 0 || ymax <= 0)
		return;
	emit(fd, EV_ABS, ABS_X, (int) ((long) x * 65535 / xmax));
	emit(fd, EV_ABS, ABS_Y, (int) ((long) y * 65535 / ymax));
	emit(fd, EV_SYN, SYN_REPORT, 0);
}

static void pointer_button(int fd, int code, int value)
{
	if (fd < 0)
		return;
	emit(fd, EV_KEY, code, value);
	emit(fd, EV_SYN, SYN_REPORT, 0);
}

int main(int argc, char **argv)
{
	int touch, out, x = 0, y = 0;
	long last_down = 0, quiet_until = 0;
	int last_x = 0, last_y = 0;
	int ymax = 0, xmax = 0, down = 0, moved = 0;
	int pointer, pfifo, dragging = 0;

	if (argc > 1)
		interval_ms = atol(argv[1]);
	if (argc > 2)
		distance = atol(argv[2]);

	touch = open_named(TOUCH_NAME);
	if (touch < 0) {
		fprintf(stderr, "pro1x-doubletap: no \"%s\" device\n", TOUCH_NAME);
		return 1;
	}
	{
		struct input_absinfo abs;

		if (ioctl(touch, EVIOCGABS(ABS_MT_POSITION_Y), &abs) == 0)
			ymax = abs.maximum;
		if (ioctl(touch, EVIOCGABS(ABS_MT_POSITION_X), &abs) == 0)
			xmax = abs.maximum;
	}
	out = open_uinput();
	if (out < 0) {
		perror("pro1x-doubletap: /dev/uinput");
		return 1;
	}
	pointer = open_pointer();
	pfifo = open_pointer_fifo();
	if (pointer < 0 || pfifo < 0)
		perror("pro1x-doubletap: camera button pointer");
	fprintf(stderr, "pro1x-doubletap: watching, interval %ld ms, distance %ld\n",
		interval_ms, distance);

	int kbd = open_named(KEYBOARD_NAME);	/* -1 until keyd made it */

	for (;;) {
		/* poll skips the entries whose fd is -1. */
		struct pollfd p[3] = {
			{ .fd = touch, .events = POLLIN },
			{ .fd = kbd, .events = POLLIN },
			{ .fd = pfifo, .events = POLLIN },
		};
		struct input_event ev;

		if (poll(p, 3, kbd >= 0 ? -1 : 5000) < 0) {
			if (errno == EINTR)
				continue;
			perror("poll");
			return 1;
		}
		if (p[0].revents & (POLLERR | POLLHUP)) {
			fprintf(stderr, "pro1x-doubletap: touch device gone\n");
			return 1;	/* Shepherd respawns us */
		}
		if (p[2].revents & POLLIN) {
			char cmd[64];
			ssize_t n = read(pfifo, cmd, sizeof cmd - 1);

			cmd[n > 0 ? n : 0] = 0;
			if (strstr(cmd, "rclick")) {
				pointer_to(pointer, x, y, xmax, ymax);
				pointer_button(pointer, BTN_RIGHT, 1);
				pointer_button(pointer, BTN_RIGHT, 0);
			} else if (strstr(cmd, "drag") && !dragging) {
				dragging = 1;
				emit(out, EV_KEY, KEY_LEFTMETA, 1);
				emit(out, EV_SYN, SYN_REPORT, 0);
				pointer_to(pointer, x, y, xmax, ymax);
				pointer_button(pointer, BTN_LEFT, 1);
			} else if (strstr(cmd, "end") && dragging) {
				dragging = 0;
				pointer_button(pointer, BTN_LEFT, 0);
				emit(out, EV_KEY, KEY_LEFTMETA, 0);
				emit(out, EV_SYN, SYN_REPORT, 0);
			}
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
				    ev.value == 1 && t >= quiet_until && panel_off() &&
				    !pocketed()) {
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
				x = ev.value, moved = 1;
			else if (ev.type == EV_ABS && ev.code == ABS_MT_POSITION_Y)
				y = ev.value, moved = 1;
			else if (ev.type == EV_KEY && ev.code == BTN_TOUCH)
				down = ev.value, moved = 1;
			else if (ev.type == EV_SYN && ev.code == SYN_REPORT && moved) {
				note_touch(x, y, xmax, ymax, down);
				if (dragging && down)
					pointer_to(pointer, x, y, xmax, ymax);
				moved = 0;
			}
			if (!(ev.type == EV_KEY && ev.code == BTN_TOUCH && ev.value == 1))
				continue;

			/* A touch-down.  Position events of this touch may follow in
			 * the same frame; the previous ones are close enough. */
			t = now_ms();
			int off = panel_off();
			/* Panel off: a double tap wakes it.  Panel on with a lock
			 * screen: a double tap blanks it (author, 2026-10-31). */
			if (t < quiet_until || pocketed() || (!off && !locker_running())) {
				last_down = 0;
				continue;
			}
			if (last_down && t - last_down < interval_ms &&
			    abs(x - last_x) < distance && abs(y - last_y) < distance) {
				if (!off && !lock_tap_allowed(y, ymax)) {
					last_down = 0;
					continue;
				}
				press_power(out);
				fprintf(stderr, "pro1x-doubletap: double tap, power key sent (%s)\n",
					off ? "wake" : "lock screen, blank");
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
