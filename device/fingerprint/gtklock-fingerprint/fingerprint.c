// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * gtklock-fingerprint: a gtklock module that unlocks with an enrolled
 * finger, through pro1x-fpd (../pro1x-fpd).
 *
 * While gtklock runs, the module keeps one "identify" request open on the
 * daemon's socket; the daemon reads the sensor only for it, and not while
 * the panel is off.  A match ends gtklock as a right password does; a miss
 * shows in the error line, and the password keeps working.  When gtklock
 * goes, the connection closes and the daemon stops reading the sensor.
 *
 * gtklock 4.0's structures are in gtklock-module.h, as in its other
 * modules (gtklock-virtkb-module, MIT).
 */

#include "gtklock-module.h"
#include <gio/gio.h>
#include <string.h>
#include <gio/gunixsocketaddress.h>

#define SOCKET "/run/pro1x-fpd.sock"
#define RETRY_S 10              /* daemon not there yet: try again */

const gchar module_name[] = "fingerprint";
const guint module_major_version = 4;
const guint module_minor_version = 0;

static struct GtkLock *lock;
static GSocketConnection *conn;
static GDataInputStream *in;
static GCancellable *cancel;

static void start(void);

static gboolean retry(gpointer data)
{
	(void)data;
	start();
	return G_SOURCE_REMOVE;
}

static void stop(gboolean again)
{
	g_clear_object(&in);
	g_clear_object(&conn);
	if (again)
		g_timeout_add_seconds(RETRY_S, retry, NULL);
}

static void show(const char *text)
{
	struct Window *w = lock ? lock->focused_window : NULL;

	if (w && w->error_label)
		gtk_label_set_text(GTK_LABEL(w->error_label), text);
}

static void got_line(GObject *src, GAsyncResult *res, gpointer data)
{
	GError *err = NULL;
	char *line = g_data_input_stream_read_line_finish(G_DATA_INPUT_STREAM(src),
							  res, NULL, &err);
	(void)data;

	if (!line) {
		/* Cancelled: gtklock is going.  Else the daemon went: try again later. */
		gboolean gone = err && g_error_matches(err, G_IO_ERROR, G_IO_ERROR_CANCELLED);

		g_clear_error(&err);
		if (!gone)
			stop(TRUE);
		return;
	}
	if (g_str_has_prefix(line, "match ")) {
		g_free(line);
		stop(FALSE);
		g_application_quit(G_APPLICATION(lock->app));
		return;
	}
	if (!strcmp(line, "nomatch")) {
		show("Fingerprint not recognised");
	} else if (g_str_has_prefix(line, "error ")) {
		/* No finger enrolled, or the sensor is down: the password only. */
		g_message("fingerprint: %s", line + 6);
		g_free(line);
		stop(FALSE);
		return;
	}
	g_free(line);
	g_data_input_stream_read_line_async(in, G_PRIORITY_DEFAULT, cancel,
					    got_line, NULL);
}

static void connected(GObject *src, GAsyncResult *res, gpointer data)
{
	GError *err = NULL;
	GOutputStream *out;
	(void)data;

	conn = g_socket_client_connect_finish(G_SOCKET_CLIENT(src), res, &err);
	g_object_unref(src);
	if (!conn) {
		gboolean gone = g_error_matches(err, G_IO_ERROR, G_IO_ERROR_CANCELLED);

		g_clear_error(&err);
		if (!gone)
			stop(TRUE);
		return;
	}
	out = g_io_stream_get_output_stream(G_IO_STREAM(conn));
	if (!g_output_stream_write_all(out, "identify\n", 9, NULL, cancel, NULL)) {
		stop(TRUE);
		return;
	}
	in = g_data_input_stream_new(g_io_stream_get_input_stream(G_IO_STREAM(conn)));
	g_data_input_stream_read_line_async(in, G_PRIORITY_DEFAULT, cancel,
					    got_line, NULL);
}

static void start(void)
{
	GSocketClient *client;
	GSocketAddress *addr;

	if (conn || g_cancellable_is_cancelled(cancel))
		return;
	client = g_socket_client_new();
	addr = g_unix_socket_address_new(SOCKET);
	g_socket_client_connect_async(client, G_SOCKET_CONNECTABLE(addr), cancel,
				      connected, NULL);
	g_object_unref(addr);
}

void on_activation(struct GtkLock *gtklock, int id)
{
	(void)id;
	lock = gtklock;
	cancel = g_cancellable_new();
	start();
}

void g_module_unload(GModule *m)
{
	(void)m;
	if (cancel)
		g_cancellable_cancel(cancel);
	stop(FALSE);
}
