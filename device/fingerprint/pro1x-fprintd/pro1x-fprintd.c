// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * pro1x-fprintd: fprintd's D-Bus interface (net.reactivated.Fprint) over
 * pro1x-fpd (../pro1x-fpd), so that fprintd clients, GNOME Settings' Users
 * page first, enrol, list and delete fingers on the Pro1X's sensor.
 *
 * One device, /net/reactivated/Fprint/Device/0.  What GNOME Settings 49
 * calls is implemented: Claim, Release, ListEnrolledFingers,
 * DeleteEnrolledFingers(2), DeleteEnrolledFinger, EnrollStart/Stop with
 * EnrollStatus, and VerifyStart/Stop with VerifyStatus, the properties.
 * Methods and signals follow fprintd 1.94's
 * net.reactivated.Fprint.Device.xml.
 *
 * pro1x-fpd keeps one set of fingers for the phone, not one per user: every
 * user that may use the sensor (root, or the user named) sees the same
 * list.  fprintd names a finger by which finger it is ("right-index-finger");
 * pro1x-fpd stores a free name.  A finger enrolled here is stored as its
 * label ("Right index finger"); one named otherwise (in the Sway menu) shows
 * as the first finger name not taken.
 *
 * Runs as root (Shepherd service pro1x-fprintd); the bus policy is
 * fprintd's own (net.reactivated.Fprint.conf).
 */

#include <gio/gio.h>
#include <gio/gunixsocketaddress.h>
#include <ctype.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCKET "/run/pro1x-fpd.sock"
#define BUS_NAME "net.reactivated.Fprint"
#define MANAGER_PATH "/net/reactivated/Fprint/Manager"
#define DEVICE_PATH "/net/reactivated/Fprint/Device/0"
#define ERR "net.reactivated.Fprint.Error."
#define ENROLL_STAGES 14        /* pro1x-fpd's ENROLL_SAMPLES */
#define MAX_PRINTS 5            /* what the TA keeps */

static const char introspection[] =
	"<node>"
	" <interface name='net.reactivated.Fprint.Manager'>"
	"  <method name='GetDevices'><arg type='ao' name='devices' direction='out'/></method>"
	"  <method name='GetDefaultDevice'><arg type='o' name='device' direction='out'/></method>"
	" </interface>"
	" <interface name='net.reactivated.Fprint.Device'>"
	"  <method name='ListEnrolledFingers'>"
	"   <arg type='s' name='username' direction='in'/>"
	"   <arg type='as' name='enrolled_fingers' direction='out'/></method>"
	"  <method name='DeleteEnrolledFingers'><arg type='s' name='username' direction='in'/></method>"
	"  <method name='DeleteEnrolledFingers2'/>"
	"  <method name='DeleteEnrolledFinger'><arg type='s' name='finger_name' direction='in'/></method>"
	"  <method name='Claim'><arg type='s' name='username' direction='in'/></method>"
	"  <method name='Release'/>"
	"  <method name='VerifyStart'><arg type='s' name='finger_name' direction='in'/></method>"
	"  <method name='VerifyStop'/>"
	"  <signal name='VerifyFingerSelected'><arg type='s' name='finger_name'/></signal>"
	"  <signal name='VerifyStatus'><arg type='s' name='result'/><arg type='b' name='done'/></signal>"
	"  <method name='EnrollStart'><arg type='s' name='finger_name' direction='in'/></method>"
	"  <method name='EnrollStop'/>"
	"  <signal name='EnrollStatus'><arg type='s' name='result'/><arg type='b' name='done'/></signal>"
	"  <property name='name' type='s' access='read'/>"
	"  <property name='num-enroll-stages' type='i' access='read'/>"
	"  <property name='scan-type' type='s' access='read'/>"
	"  <property name='finger-present' type='b' access='read'/>"
	"  <property name='finger-needed' type='b' access='read'/>"
	" </interface>"
	"</node>";

/* fprintd's finger names, and the order fingers without one get them. */
static const char *const fingers[] = {
	"right-index-finger", "left-index-finger", "right-thumb", "left-thumb",
	"right-middle-finger", "left-middle-finger", "right-ring-finger",
	"left-ring-finger", "right-little-finger", "left-little-finger",
};
#define N_FINGERS (sizeof(fingers) / sizeof(fingers[0]))

static GDBusConnection *bus;
static char *claimer;           /* unique bus name of the client holding the device */
static guint claimer_watch;

enum op { OP_NONE, OP_ENROLL, OP_VERIFY };
static enum op op;
static GSocketConnection *op_conn;
static GDataInputStream *op_in;
static GCancellable *op_cancel;

/* ── pro1x-fpd, synchronously (list, remove) ─────────────────────────── */

struct print {
	unsigned id;
	char name[200];
	const char *finger;     /* fprintd's name for it */
};

/* Send one request; the reply lines up to "ok" or "error ..." into buf. */
static int fpd_request(const char *req, char *buf, size_t size)
{
	struct sockaddr_un sa = { .sun_family = AF_UNIX };
	size_t got = 0;
	int fd;

	strcpy(sa.sun_path, SOCKET);
	fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0 || connect(fd, (struct sockaddr *)&sa, sizeof(sa)) ||
	    write(fd, req, strlen(req)) < 0) {
		if (fd >= 0)
			close(fd);
		return -1;
	}
	while (got < size - 1) {
		ssize_t n = read(fd, buf + got, size - 1 - got);

		if (n <= 0)
			break;
		got += n;
		buf[got] = 0;
		if (!strncmp(buf + got - (got >= 3 ? 3 : got), "ok\n", 3) ||
		    strstr(buf, "error "))
			break;
	}
	buf[got] = 0;
	close(fd);
	return 0;
}

/* The finger name a label or free name stands for, or NULL. */
static const char *finger_of_name(const char *name)
{
	for (size_t i = 0; i < N_FINGERS; i++) {
		const char *f = fingers[i], *n = name;

		while (*f && *n && (*f == '-' ? *n == ' ' || *n == '-' :
				    tolower((unsigned char)*n) == *f))
			f++, n++;
		if (!*f && !*n)
			return fingers[i];
	}
	return NULL;
}

/* The label pro1x-fpd stores for a finger name: "Right index finger". */
static void label_of(const char *finger, char *out, size_t size)
{
	snprintf(out, size, "%s", finger);
	for (char *p = out; *p; p++)
		if (*p == '-')
			*p = ' ';
	out[0] = toupper((unsigned char)out[0]);
}

/* The prints on file, each with its finger name; -1 if pro1x-fpd is down. */
static int list_prints(struct print *p, int max)
{
	char buf[4096], *line, *save = NULL;
	int n = 0;

	if (fpd_request("list\n", buf, sizeof(buf)) || strstr(buf, "error "))
		return -1;
	for (line = strtok_r(buf, "\n", &save); line && n < max;
	     line = strtok_r(NULL, "\n", &save)) {
		char *sp;

		if (strncmp(line, "finger ", 7))
			continue;
		p[n].id = strtoul(line + 7, &sp, 10);
		snprintf(p[n].name, sizeof(p[n].name), "%s", *sp ? sp + 1 : "");
		p[n].finger = finger_of_name(p[n].name);
		n++;
	}
	/* Free names get the first finger names nobody has. */
	for (int i = 0; i < n; i++) {
		for (size_t f = 0; !p[i].finger && f < N_FINGERS; f++) {
			gboolean taken = FALSE;

			for (int j = 0; j < n; j++)
				taken |= p[j].finger == fingers[f];
			if (!taken)
				p[i].finger = fingers[f];
		}
	}
	return n;
}

static int remove_print(unsigned id)
{
	char req[32], buf[256];

	snprintf(req, sizeof(req), "remove %u\n", id);
	return fpd_request(req, buf, sizeof(buf)) || strncmp(buf, "ok", 2) ? -1 : 0;
}

/* ── Callers ────────────────────────────────────────────────────────── */

static uid_t caller_uid(const char *sender)
{
	g_autoptr (GVariant) r = g_dbus_connection_call_sync(
		bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
		"org.freedesktop.DBus", "GetConnectionUnixUser",
		g_variant_new("(s)", sender), G_VARIANT_TYPE("(u)"),
		G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL);
	guint32 uid;

	if (!r)
		return (uid_t)-1;
	g_variant_get(r, "(u)", &uid);
	return uid;
}

/* May sender act for username ("" is the sender itself)? */
static gboolean may_act_for(const char *sender, const char *username)
{
	uid_t uid = caller_uid(sender);
	struct passwd *pw;

	if (uid == 0)
		return TRUE;
	if (uid == (uid_t)-1)
		return FALSE;
	if (!username || !*username)
		return TRUE;
	pw = getpwnam(username);
	return pw && pw->pw_uid == uid;
}

static gboolean claimed_by(GDBusMethodInvocation *inv)
{
	if (claimer && !strcmp(claimer, g_dbus_method_invocation_get_sender(inv)))
		return TRUE;
	g_dbus_method_invocation_return_dbus_error(inv, ERR "ClaimDevice",
						   "Claim the device first");
	return FALSE;
}

/* ── Enrolment and verification, through an open pro1x-fpd request ── */

static void emit(const char *signal, const char *result, gboolean done)
{
	g_dbus_connection_emit_signal(bus, claimer, DEVICE_PATH,
				      "net.reactivated.Fprint.Device", signal,
				      g_variant_new("(sb)", result, done), NULL);
}

static void op_end(void)
{
	if (op_cancel)
		g_cancellable_cancel(op_cancel);
	g_clear_object(&op_in);
	g_clear_object(&op_conn);
	g_clear_object(&op_cancel);
	op = OP_NONE;
}

/* A pro1x-fpd reply line as fprintd's status, and whether it ends the operation. */
static const char *status_of(enum op o, const char *line, gboolean *done)
{
	*done = FALSE;
	if (o == OP_ENROLL) {
		if (g_str_has_prefix(line, "sample "))
			return "enroll-stage-passed";
		if (g_str_has_prefix(line, "retry partial"))
			return "enroll-finger-not-centered";
		if (g_str_has_prefix(line, "retry this finger")) {
			*done = TRUE;
			return "enroll-duplicate";
		}
		if (g_str_has_prefix(line, "retry "))
			return "enroll-retry-scan";
		*done = TRUE;
		if (g_str_has_prefix(line, "enrolled "))
			return "enroll-completed";
		if (strstr(line, "five fingers"))
			return "enroll-data-full";
		if (g_str_has_prefix(line, "error "))
			return "enroll-failed";
	} else {
		*done = TRUE;
		if (g_str_has_prefix(line, "match "))
			return "verify-match";
		if (!strcmp(line, "nomatch"))
			return "verify-no-match";
		if (g_str_has_prefix(line, "error "))
			return "verify-unknown-error";
	}
	*done = FALSE;
	return NULL;            /* "touch", "lift": nothing to say */
}

static void op_line(GObject *src, GAsyncResult *res, gpointer data)
{
	g_autoptr (GError) err = NULL;
	g_autofree char *line = g_data_input_stream_read_line_finish(
		G_DATA_INPUT_STREAM(src), res, NULL, &err);
	enum op o = GPOINTER_TO_INT(data);
	const char *status;
	gboolean done;

	if (!line && g_error_matches(err, G_IO_ERROR, G_IO_ERROR_CANCELLED))
		return;         /* stopped or released */
	if (!line) {
		emit(o == OP_ENROLL ? "EnrollStatus" : "VerifyStatus",
		     o == OP_ENROLL ? "enroll-disconnected" : "verify-disconnected", TRUE);
		op_end();
		return;
	}
	status = status_of(o, line, &done);
	if (status)
		emit(o == OP_ENROLL ? "EnrollStatus" : "VerifyStatus", status, done);
	if (done) {
		op_end();
		return;
	}
	g_data_input_stream_read_line_async(op_in, G_PRIORITY_DEFAULT, op_cancel,
					    op_line, data);
}

/* Open a request on pro1x-fpd and follow its replies; FALSE if it is down. */
static gboolean op_start(enum op o, const char *req)
{
	g_autoptr (GSocketClient) client = g_socket_client_new();
	g_autoptr (GSocketAddress) addr = g_unix_socket_address_new(SOCKET);
	GOutputStream *out;

	op_cancel = g_cancellable_new();
	op_conn = g_socket_client_connect(client, G_SOCKET_CONNECTABLE(addr),
					  op_cancel, NULL);
	if (!op_conn) {
		op_end();
		return FALSE;
	}
	out = g_io_stream_get_output_stream(G_IO_STREAM(op_conn));
	if (!g_output_stream_write_all(out, req, strlen(req), NULL, op_cancel, NULL)) {
		op_end();
		return FALSE;
	}
	op = o;
	op_in = g_data_input_stream_new(g_io_stream_get_input_stream(G_IO_STREAM(op_conn)));
	g_data_input_stream_read_line_async(op_in, G_PRIORITY_DEFAULT, op_cancel,
					    op_line, GINT_TO_POINTER(o));
	return TRUE;
}

/* ── Claiming ───────────────────────────────────────────────────────── */

static void release(void)
{
	op_end();
	if (claimer_watch)
		g_bus_unwatch_name(claimer_watch);
	claimer_watch = 0;
	g_clear_pointer(&claimer, g_free);
}

static void claimer_vanished(GDBusConnection *c, const char *name, gpointer data)
{
	(void)c, (void)name, (void)data;
	release();
}

/* ── Methods ────────────────────────────────────────────────────────── */

static void return_fingers(GDBusMethodInvocation *inv)
{
	struct print p[MAX_PRINTS];
	int n = list_prints(p, MAX_PRINTS);
	GVariantBuilder b;

	if (n < 0) {
		g_dbus_method_invocation_return_dbus_error(inv, ERR "Internal",
							   "pro1x-fpd is not running");
		return;
	}
	if (n == 0) {
		g_dbus_method_invocation_return_dbus_error(inv, ERR "NoEnrolledPrints",
							   "No fingers enrolled");
		return;
	}
	g_variant_builder_init(&b, G_VARIANT_TYPE("as"));
	for (int i = 0; i < n; i++)
		g_variant_builder_add(&b, "s", p[i].finger);
	g_dbus_method_invocation_return_value(inv, g_variant_new("(as)", &b));
}

/* Remove the prints of finger (NULL: all); how many, or -1 on a failure. */
static int delete_prints(const char *finger)
{
	struct print p[MAX_PRINTS];
	int n = list_prints(p, MAX_PRINTS), removed = 0;

	if (n < 0)
		return -1;
	for (int i = 0; i < n; i++) {
		if (finger && strcmp(p[i].finger, finger))
			continue;
		if (remove_print(p[i].id))
			return -1;
		removed++;
	}
	return removed;
}

static void return_deleted(GDBusMethodInvocation *inv, int removed)
{
	if (removed < 0)
		g_dbus_method_invocation_return_dbus_error(inv, ERR "Internal",
							   "Could not delete");
	else if (removed == 0)
		g_dbus_method_invocation_return_dbus_error(inv, ERR "NoEnrolledPrints",
							   "No such finger enrolled");
	else
		g_dbus_method_invocation_return_value(inv, NULL);
}

static gboolean valid_finger(const char *f)
{
	for (size_t i = 0; i < N_FINGERS; i++)
		if (!strcmp(f, fingers[i]))
			return TRUE;
	return FALSE;
}

static void device_call(GDBusConnection *c, const char *sender, const char *path,
			const char *iface, const char *method, GVariant *params,
			GDBusMethodInvocation *inv, gpointer data)
{
	const char *arg = NULL;
	(void)c, (void)path, (void)iface, (void)data;

	if (g_variant_n_children(params) == 1)
		g_variant_get(params, "(&s)", &arg);

	if (!strcmp(method, "Claim")) {
		if (claimer) {
			g_dbus_method_invocation_return_dbus_error(inv, ERR "AlreadyInUse",
								   "Device was already claimed");
		} else if (!may_act_for(sender, arg)) {
			g_dbus_method_invocation_return_dbus_error(inv, ERR "PermissionDenied",
								   "Not allowed for this user");
		} else {
			claimer = g_strdup(sender);
			claimer_watch = g_bus_watch_name_on_connection(
				bus, sender, G_BUS_NAME_WATCHER_FLAGS_NONE, NULL,
				claimer_vanished, NULL, NULL);
			g_dbus_method_invocation_return_value(inv, NULL);
		}
	} else if (!strcmp(method, "Release")) {
		if (claimed_by(inv)) {
			release();
			g_dbus_method_invocation_return_value(inv, NULL);
		}
	} else if (!strcmp(method, "ListEnrolledFingers")) {
		if (!may_act_for(sender, arg))
			g_dbus_method_invocation_return_dbus_error(inv, ERR "PermissionDenied",
								   "Not allowed for this user");
		else
			return_fingers(inv);
	} else if (!strcmp(method, "DeleteEnrolledFingers")) {
		if (!may_act_for(sender, arg))
			g_dbus_method_invocation_return_dbus_error(inv, ERR "PermissionDenied",
								   "Not allowed for this user");
		else
			return_deleted(inv, delete_prints(NULL));
	} else if (!strcmp(method, "DeleteEnrolledFingers2")) {
		if (claimed_by(inv))
			return_deleted(inv, delete_prints(NULL));
	} else if (!strcmp(method, "DeleteEnrolledFinger")) {
		if (claimed_by(inv))
			return_deleted(inv, delete_prints(arg));
	} else if (!strcmp(method, "EnrollStart")) {
		char req[64], label[40];

		if (!claimed_by(inv))
			return;
		if (!valid_finger(arg)) {
			g_dbus_method_invocation_return_dbus_error(inv, ERR "InvalidFingername",
								   "Not a finger name");
			return;
		}
		if (op != OP_NONE) {
			g_dbus_method_invocation_return_dbus_error(inv, ERR "AlreadyInUse",
								   "An operation is running");
			return;
		}
		/* As fprintd: enrolling a finger again replaces its print. */
		delete_prints(arg);
		label_of(arg, label, sizeof(label));
		snprintf(req, sizeof(req), "enroll %s\n", label);
		if (!op_start(OP_ENROLL, req)) {
			g_dbus_method_invocation_return_dbus_error(inv, ERR "Internal",
								   "pro1x-fpd is not running");
			return;
		}
		g_dbus_method_invocation_return_value(inv, NULL);
	} else if (!strcmp(method, "VerifyStart")) {
		if (!claimed_by(inv))
			return;
		if (op != OP_NONE) {
			g_dbus_method_invocation_return_dbus_error(inv, ERR "AlreadyInUse",
								   "An operation is running");
			return;
		}
		if (!op_start(OP_VERIFY, "identify\n")) {
			g_dbus_method_invocation_return_dbus_error(inv, ERR "Internal",
								   "pro1x-fpd is not running");
			return;
		}
		g_dbus_method_invocation_return_value(inv, NULL);
		g_dbus_connection_emit_signal(bus, claimer, DEVICE_PATH,
					      "net.reactivated.Fprint.Device",
					      "VerifyFingerSelected",
					      g_variant_new("(s)", "any"), NULL);
	} else if (!strcmp(method, "EnrollStop") || !strcmp(method, "VerifyStop")) {
		enum op want = method[0] == 'E' ? OP_ENROLL : OP_VERIFY;

		if (!claimed_by(inv))
			return;
		if (op != want) {
			g_dbus_method_invocation_return_dbus_error(inv, ERR "NoActionInProgress",
								   "Nothing to stop");
			return;
		}
		op_end();       /* the closed request cancels it in pro1x-fpd */
		g_dbus_method_invocation_return_value(inv, NULL);
	} else {
		g_dbus_method_invocation_return_dbus_error(inv, "org.freedesktop.DBus.Error.UnknownMethod",
							   method);
	}
}

static GVariant *device_property(GDBusConnection *c, const char *sender,
				 const char *path, const char *iface,
				 const char *prop, GError **error, gpointer data)
{
	(void)c, (void)sender, (void)path, (void)iface, (void)error, (void)data;

	if (!strcmp(prop, "name"))
		return g_variant_new_string("MicroArray fingerprint sensor (pro1x-fpd)");
	if (!strcmp(prop, "num-enroll-stages"))
		return g_variant_new_int32(ENROLL_STAGES);
	if (!strcmp(prop, "scan-type"))
		return g_variant_new_string("press");
	if (!strcmp(prop, "finger-present"))
		return g_variant_new_boolean(FALSE);
	if (!strcmp(prop, "finger-needed"))
		return g_variant_new_boolean(op != OP_NONE);
	return NULL;
}

static void manager_call(GDBusConnection *c, const char *sender, const char *path,
			 const char *iface, const char *method, GVariant *params,
			 GDBusMethodInvocation *inv, gpointer data)
{
	(void)c, (void)sender, (void)path, (void)iface, (void)params, (void)data;

	if (!strcmp(method, "GetDevices")) {
		const char *devices[] = { DEVICE_PATH };

		g_dbus_method_invocation_return_value(
			inv, g_variant_new("(@ao)", g_variant_new_objv(devices, 1)));
	} else {
		g_dbus_method_invocation_return_value(inv, g_variant_new("(o)", DEVICE_PATH));
	}
}

static const GDBusInterfaceVTable manager_vtable = { manager_call, NULL, NULL, { 0 } };
static const GDBusInterfaceVTable device_vtable = { device_call, device_property, NULL, { 0 } };

static void bus_acquired(GDBusConnection *c, const char *name, gpointer data)
{
	GDBusNodeInfo *info = data;
	g_autoptr (GError) err = NULL;
	(void)name;

	bus = c;
	if (!g_dbus_connection_register_object(c, MANAGER_PATH, info->interfaces[0],
					       &manager_vtable, NULL, NULL, &err) ||
	    !g_dbus_connection_register_object(c, DEVICE_PATH, info->interfaces[1],
					       &device_vtable, NULL, NULL, &err))
		g_error("could not register the objects: %s", err->message);
}

static void name_lost(GDBusConnection *c, const char *name, gpointer data)
{
	(void)c, (void)data;
	g_printerr("pro1x-fprintd: lost or could not own %s (fprintd running?)\n", name);
	exit(1);
}

int main(void)
{
	GDBusNodeInfo *info = g_dbus_node_info_new_for_xml(introspection, NULL);
	GMainLoop *loop = g_main_loop_new(NULL, FALSE);

	g_bus_own_name(G_BUS_TYPE_SYSTEM, BUS_NAME, G_BUS_NAME_OWNER_FLAGS_NONE,
		       bus_acquired, NULL, name_lost, info, NULL);
	g_main_loop_run(loop);
	return 0;
}
