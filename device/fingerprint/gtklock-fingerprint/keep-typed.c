// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * gtklock-keep-typed: what was typed in the password field survives a new
 * gtklock.
 *
 * gtklock cannot be turned with the panel (it dies, "Error 71"), so
 * pro1x-lock --rotate replaces it on each turn, and a password being typed
 * was lost (author, 2026-11-20).  On SIGUSR2 (SIGUSR1 is gtklock's own,
 * for --daemonize) this module writes the field's text to
 * $XDG_RUNTIME_DIR/pro1x-lock-typed, readable by the user only; pro1x-lock
 * sends it just before the swap.  A new gtklock that finds the file, less
 * than 10 s old and the user's own, puts the text back in its field and
 * deletes the file at once; the copy in memory is wiped 5 s later.
 *
 * gtklock 4.0's structures are in gtklock-module.h, as in the fingerprint
 * module beside it.
 */

#include "gtklock-module.h"
#include <glib-unix.h>
#include <glib/gstdio.h>
#include <signal.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

const gchar module_name[] = "keep-typed";
const guint module_major_version = 4;
const guint module_minor_version = 0;

static struct GtkLock *lock;
static gchar *restore;          /* the text to put back, briefly */

static gchar *typed_path(void)
{
	return g_build_filename(g_get_user_runtime_dir(), "pro1x-lock-typed", NULL);
}

static void wipe(void)
{
	if (restore) {
		memset(restore, 0, strlen(restore));
		g_free(restore);
		restore = NULL;
	}
}

static gboolean wipe_later(gpointer data)
{
	(void)data;
	wipe();
	return G_SOURCE_REMOVE;
}

static struct Window *any_window(void)
{
	if (!lock)
		return NULL;
	if (lock->focused_window)
		return lock->focused_window;
	if (lock->windows && lock->windows->len)
		return g_array_index(lock->windows, struct Window *, 0);
	return NULL;
}

static gboolean save(gpointer data)
{
	struct Window *w = any_window();
	gchar *path;
	mode_t old;

	(void)data;
	if (!w || !w->input_field)
		return G_SOURCE_CONTINUE;
	path = typed_path();
	old = umask(077);
	g_file_set_contents(path, gtk_entry_get_text(GTK_ENTRY(w->input_field)), -1, NULL);
	umask(old);
	g_chmod(path, 0600);
	g_free(path);
	return G_SOURCE_CONTINUE;
}

static void fill(struct Window *w)
{
	if (!restore || !w || !w->input_field)
		return;
	gtk_entry_set_text(GTK_ENTRY(w->input_field), restore);
	gtk_editable_set_position(GTK_EDITABLE(w->input_field), -1);
}

void on_activation(struct GtkLock *gtklock, int id)
{
	gchar *path = typed_path();
	GStatBuf st;

	(void)id;
	lock = gtklock;
	g_unix_signal_add(SIGUSR2, save, NULL);
	if (g_stat(path, &st) == 0 && st.st_uid == getuid() &&
	    time(NULL) - st.st_mtime < 10)
		g_file_get_contents(path, &restore, NULL, NULL);
	g_unlink(path);
	g_free(path);
	if (restore) {
		for (guint i = 0; lock->windows && i < lock->windows->len; i++)
			fill(g_array_index(lock->windows, struct Window *, i));
		g_timeout_add_seconds(5, wipe_later, NULL);
	}
}

/* Windows made after the activation (an output that comes later). */
void on_window_create(struct GtkLock *gtklock, struct Window *win)
{
	(void)gtklock;
	fill(win);
}

void g_module_unload(GModule *m)
{
	(void)m;
	wipe();
}
