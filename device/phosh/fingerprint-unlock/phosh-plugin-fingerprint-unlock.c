// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * fingerprint-unlock: a Phosh lock-screen plugin that unlocks with an
 * enrolled finger, through pro1x-fpd (device/fingerprint/pro1x-fpd).
 *
 * Phosh creates the lock screen's plugins when it locks and destroys them
 * when it unlocks.  While the plugin lives, it keeps one "identify" request
 * open on the daemon's socket; the daemon reads the sensor only for it, and
 * not while the panel is off.  A match unlocks as a right PIN does; a miss
 * shows on the plugin's page, and the PIN keeps working.  When the lock
 * screen goes, the connection closes and the daemon stops reading.
 *
 * Built inside Phosh's tree (phosh-pro1x in packages/misc.scm), which also
 * exports the two lock-screen-manager functions it calls.  The same as the
 * gtklock module (device/fingerprint/gtklock-fingerprint) otherwise.
 */

#define G_LOG_DOMAIN "phosh-plugin-fingerprint-unlock"

#include "phosh-plugin.h"
#include "shell.h"
#include "lockscreen-manager.h"

#include <gio/gio.h>
#include <gio/gunixsocketaddress.h>
#include <gtk/gtk.h>
#include <string.h>

#define SOCKET "/run/pro1x-fpd.sock"
#define RETRY_S 10              /* daemon not there yet: try again */

#define PHOSH_TYPE_FINGERPRINT_UNLOCK (phosh_fingerprint_unlock_get_type ())
G_DECLARE_FINAL_TYPE (PhoshFingerprintUnlock, phosh_fingerprint_unlock,
                      PHOSH, FINGERPRINT_UNLOCK, GtkBox)

struct _PhoshFingerprintUnlock {
  GtkBox             parent;
  GtkWidget         *label;
  GSocketConnection *conn;
  GDataInputStream  *in;
  GCancellable      *cancel;
  guint              retry_id;
};

G_DEFINE_TYPE (PhoshFingerprintUnlock, phosh_fingerprint_unlock, GTK_TYPE_BOX)

static void start (PhoshFingerprintUnlock *self);

static gboolean
retry (gpointer data)
{
  PhoshFingerprintUnlock *self = data;

  self->retry_id = 0;
  start (self);
  return G_SOURCE_REMOVE;
}

static void
stop (PhoshFingerprintUnlock *self, gboolean again)
{
  g_clear_object (&self->in);
  g_clear_object (&self->conn);
  if (again && !self->retry_id)
    self->retry_id = g_timeout_add_seconds (RETRY_S, retry, self);
}

static void
unlock (void)
{
  PhoshLockscreenManager *lm =
    phosh_shell_get_lockscreen_manager (phosh_shell_get_default ());

  phosh_lockscreen_manager_set_locked (lm, FALSE);
}

static void
got_line (GObject *src, GAsyncResult *res, gpointer data)
{
  g_autoptr (GError) err = NULL;
  char *line = g_data_input_stream_read_line_finish (G_DATA_INPUT_STREAM (src),
                                                     res, NULL, &err);
  PhoshFingerprintUnlock *self;

  /* Cancelled: the lock screen is going, and self with it. */
  if (!line && g_error_matches (err, G_IO_ERROR, G_IO_ERROR_CANCELLED))
    return;
  self = PHOSH_FINGERPRINT_UNLOCK (data);
  if (!line) {
    stop (self, TRUE);          /* the daemon went: try again later */
    return;
  }
  if (g_str_has_prefix (line, "match ")) {
    g_free (line);
    stop (self, FALSE);
    unlock ();                  /* destroys self */
    return;
  }
  if (!strcmp (line, "nomatch")) {
    gtk_label_set_text (GTK_LABEL (self->label), "Fingerprint not recognised");
  } else if (g_str_has_prefix (line, "error ")) {
    /* No finger enrolled, or the sensor is down: the PIN only. */
    g_message ("%s", line + 6);
    gtk_widget_hide (GTK_WIDGET (self));
    g_free (line);
    stop (self, FALSE);
    return;
  }
  g_free (line);
  g_data_input_stream_read_line_async (self->in, G_PRIORITY_DEFAULT, self->cancel,
                                       got_line, self);
}

static void
connected (GObject *src, GAsyncResult *res, gpointer data)
{
  g_autoptr (GError) err = NULL;
  GSocketConnection *conn = g_socket_client_connect_finish (G_SOCKET_CLIENT (src),
                                                            res, &err);
  PhoshFingerprintUnlock *self;
  GOutputStream *out;

  if (!conn && g_error_matches (err, G_IO_ERROR, G_IO_ERROR_CANCELLED))
    return;
  self = PHOSH_FINGERPRINT_UNLOCK (data);
  if (!conn) {
    stop (self, TRUE);
    return;
  }
  self->conn = conn;
  out = g_io_stream_get_output_stream (G_IO_STREAM (conn));
  if (!g_output_stream_write_all (out, "identify\n", 9, NULL, self->cancel, NULL)) {
    stop (self, TRUE);
    return;
  }
  self->in = g_data_input_stream_new (g_io_stream_get_input_stream (G_IO_STREAM (conn)));
  g_data_input_stream_read_line_async (self->in, G_PRIORITY_DEFAULT, self->cancel,
                                       got_line, self);
}

static void
start (PhoshFingerprintUnlock *self)
{
  g_autoptr (GSocketClient) client = g_socket_client_new ();
  g_autoptr (GSocketAddress) addr = g_unix_socket_address_new (SOCKET);

  if (self->conn || g_cancellable_is_cancelled (self->cancel))
    return;
  g_socket_client_connect_async (client, G_SOCKET_CONNECTABLE (addr), self->cancel,
                                 connected, self);
}

static void
phosh_fingerprint_unlock_dispose (GObject *object)
{
  PhoshFingerprintUnlock *self = PHOSH_FINGERPRINT_UNLOCK (object);

  g_cancellable_cancel (self->cancel);
  g_clear_handle_id (&self->retry_id, g_source_remove);
  stop (self, FALSE);
  g_clear_object (&self->cancel);

  G_OBJECT_CLASS (phosh_fingerprint_unlock_parent_class)->dispose (object);
}

static void
phosh_fingerprint_unlock_class_init (PhoshFingerprintUnlockClass *klass)
{
  G_OBJECT_CLASS (klass)->dispose = phosh_fingerprint_unlock_dispose;
}

static void
phosh_fingerprint_unlock_init (PhoshFingerprintUnlock *self)
{
  gtk_orientable_set_orientation (GTK_ORIENTABLE (self), GTK_ORIENTATION_VERTICAL);
  gtk_widget_set_valign (GTK_WIDGET (self), GTK_ALIGN_CENTER);
  self->label = gtk_label_new ("Touch the fingerprint sensor to unlock");
  gtk_label_set_line_wrap (GTK_LABEL (self->label), TRUE);
  gtk_container_add (GTK_CONTAINER (self), self->label);
  gtk_widget_show (self->label);

  self->cancel = g_cancellable_new ();
  /* No daemon on this system (the fingerprint service is off): nothing to show. */
  if (!g_file_test (SOCKET, G_FILE_TEST_EXISTS))
    gtk_widget_hide (GTK_WIDGET (self));
  start (self);
}

char **g_io_phosh_plugin_fingerprint_unlock_query (void);

void
g_io_module_load (GIOModule *module)
{
  g_type_module_use (G_TYPE_MODULE (module));

  g_io_extension_point_implement (PHOSH_PLUGIN_EXTENSION_POINT_LOCKSCREEN_WIDGET,
                                  PHOSH_TYPE_FINGERPRINT_UNLOCK,
                                  PLUGIN_NAME,
                                  10);
}

void
g_io_module_unload (GIOModule *module)
{
}

char **
g_io_phosh_plugin_fingerprint_unlock_query (void)
{
  char *extension_points[] = { PHOSH_PLUGIN_EXTENSION_POINT_LOCKSCREEN_WIDGET, NULL };

  return g_strdupv (extension_points);
}
