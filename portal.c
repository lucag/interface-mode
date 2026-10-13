/*
 * portal.c
 *
 * Linux backend: reads the Interface Mode from the XDG Desktop Portal
 * (org.freedesktop.appearance color-scheme). See docs/adr/0001.
 */

#include "interface-mode.h"

#include <errno.h>
#include <fcntl.h>
#include <gio/gio.h>
#include <glib-unix.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define PORTAL_NAME "org.freedesktop.portal.Desktop"
#define PORTAL_PATH "/org/freedesktop/portal/desktop"
#define SETTINGS_IFACE "org.freedesktop.portal.Settings"
#define APPEARANCE_NS "org.freedesktop.appearance"
#define COLOR_SCHEME_KEY "color-scheme"

enum { COLOR_SCHEME_PREFER_DARK = 1 };

/* Call Settings.<method>(appearance, color-scheme) and return its value. */
static GVariant *call_settings(GDBusConnection *bus, const char *method,
                               GError **err) {
  return g_dbus_connection_call_sync(
      bus, PORTAL_NAME, PORTAL_PATH, SETTINGS_IFACE, method,
      g_variant_new("(ss)", APPEARANCE_NS, COLOR_SCHEME_KEY),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, -1, NULL, err);
}

/* Move a GError's message into a malloc'ed string, freeing the error. */
static char *take_message(GError *err) {
  char *message = strdup(err->message);
  g_error_free(err);
  return message;
}

/* Strip any number of variant wrappers, taking over the caller's ref. The
 * deprecated Settings.Read wraps the value in one more than ReadOne does. */
static GVariant *unwrap(GVariant *value) {
  while (g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
    GVariant *inner = g_variant_get_variant(value);
    g_variant_unref(value);
    value = inner;
  }
  return value;
}

/* The Interface Mode a color-scheme value stands for; false if it isn't one. */
static bool mode_from_color_scheme(GVariant *value, Mode *mode) {
  if (!g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) {
    return false;
  }
  /* 0 is "no preference", which counts as Light; 2 is "prefer light". */
  *mode = g_variant_get_uint32(value) == COLOR_SCHEME_PREFER_DARK ? MODE_DARK
                                                                  : MODE_LIGHT;
  return true;
}

/* Read color-scheme over `bus`; on failure set *error and return false. */
static bool read_mode(GDBusConnection *bus, Mode *mode, char **error) {
  GError *err = NULL;
  GVariant *reply = call_settings(bus, "ReadOne", &err);
  /* Portals before Settings version 2 only have the deprecated Read. */
  if (reply == NULL &&
      g_error_matches(err, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD)) {
    g_clear_error(&err);
    reply = call_settings(bus, "Read", &err);
  }
  if (reply == NULL) {
    *error = take_message(err);
    return false;
  }

  GVariant *value = unwrap(g_variant_get_child_value(reply, 0));
  g_variant_unref(reply);
  bool ok = mode_from_color_scheme(value, mode);
  if (!ok) {
    *error = g_strdup_printf("unexpected color-scheme type '%s' from portal",
                             g_variant_get_type_string(value));
  }
  g_variant_unref(value);
  return ok;
}

static GDBusConnection *session_bus(char **error) {
  GError *err = NULL;
  GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &err);
  if (bus == NULL) {
    *error = take_message(err);
  }
  return bus;
}

bool platform_read_mode(Mode *mode, char **error) {
  GDBusConnection *bus = session_bus(error);
  if (bus == NULL) {
    return false;
  }
  bool ok = read_mode(bus, mode, error);
  g_object_unref(bus);
  return ok;
}

typedef struct {
  ModeCallback observe;
  void *data;
} Observer;

static void on_setting_changed(GDBusConnection *bus, const char *sender,
                               const char *path, const char *iface,
                               const char *signal, GVariant *params,
                               gpointer user_data) {
  (void)bus, (void)sender, (void)path, (void)iface, (void)signal;
  Observer *observer = user_data;
  const char *ns, *key;
  GVariant *value;
  g_variant_get(params, "(&s&sv)", &ns, &key, &value);
  value = unwrap(value);
  Mode mode;
  if (strcmp(ns, APPEARANCE_NS) == 0 && strcmp(key, COLOR_SCHEME_KEY) == 0 &&
      mode_from_color_scheme(value, &mode)) {
    observer->observe(mode, observer->data);
  }
  g_variant_unref(value);
}

/*
 * SIGINT and SIGTERM ask the Watcher to stop. Their handler only writes a
 * byte to this pipe, which the main loop watches. It stays installed for the
 * rest of the process, so a second request during shutdown (Ctrl+C reaching a
 * whole process group, then a parent asking again) is absorbed instead of
 * killing the Watcher on its way out, whichever thread it is delivered to.
 *
 * Connecting to the bus and the first read can block, and no loop is running
 * yet to see the pipe; there is nothing to undo either, and every Report so
 * far has been flushed. So while stop_ends_process is set, a stop request
 * ends the process at once, with the status a stopped Watcher exits with.
 */
static int stop_pipe[2] = {-1, -1};
static volatile sig_atomic_t stop_ends_process;

static void request_stop(int signum) {
  (void)signum;
  if (stop_ends_process) {
    _exit(EXIT_SUCCESS);
  }
  int saved_errno = errno;
  /* A full pipe means a stop request is already pending. */
  ssize_t written = write(stop_pipe[1], "", 1);
  (void)written;
  errno = saved_errno;
}

/* Consume the stop requests that have arrived so far. */
static void drain_stop_requests(void) {
  char requests[64];
  while (read(stop_pipe[0], requests, sizeof requests) > 0) {
  }
}

static void close_stop_pipe(void) {
  for (int i = 0; i < 2; i++) {
    if (stop_pipe[i] != -1) {
      close(stop_pipe[i]);
      stop_pipe[i] = -1;
    }
  }
}

static bool catch_stop_requests(char **error) {
  if (stop_pipe[0] != -1) {
    /* Requests that reached an earlier Watcher on their way out were its. */
    drain_stop_requests();
    return true;
  }
  GError *err = NULL;
  if (!g_unix_open_pipe(stop_pipe, FD_CLOEXEC, &err) ||
      !g_unix_set_fd_nonblocking(stop_pipe[0], TRUE, &err) ||
      !g_unix_set_fd_nonblocking(stop_pipe[1], TRUE, &err)) {
    *error = take_message(err);
    close_stop_pipe();
    return false;
  }
  struct sigaction action = {0};
  action.sa_handler = request_stop;
  action.sa_flags = SA_RESTART;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGINT, &action, NULL) != 0 ||
      sigaction(SIGTERM, &action, NULL) != 0) {
    *error = strdup(strerror(errno));
    signal(SIGINT, SIG_DFL);
    close_stop_pipe();
    return false;
  }
  return true;
}

static gboolean on_stop_requested(int fd, GIOCondition condition,
                                  gpointer loop) {
  (void)fd, (void)condition;
  drain_stop_requests();
  g_main_loop_quit(loop);
  return G_SOURCE_CONTINUE;
}

typedef struct {
  GMainLoop *loop;
  bool vanished;
} PortalPresence;

static void on_portal_vanished(GDBusConnection *bus, const char *name,
                               gpointer user_data) {
  (void)bus, (void)name;
  PortalPresence *presence = user_data;
  presence->vanished = true;
  g_main_loop_quit(presence->loop);
}

bool platform_watch(ModeCallback observe, void *data, char **error) {
  if (!catch_stop_requests(error)) {
    return false;
  }
  stop_ends_process = 1;
  GDBusConnection *bus = session_bus(error);
  if (bus == NULL) {
    stop_ends_process = 0;
    return false;
  }
  /* Set everything up before the first read, so neither a change nor a stop
   * request can slip in between it and the loop. */
  GMainLoop *loop = g_main_loop_new(NULL, FALSE);
  guint stop_source =
      g_unix_fd_add(stop_pipe[0], G_IO_IN, on_stop_requested, loop);
  Observer observer = {observe, data};
  guint subscription = g_dbus_connection_signal_subscribe(
      bus, PORTAL_NAME, SETTINGS_IFACE, "SettingChanged", PORTAL_PATH,
      APPEARANCE_NS, G_DBUS_SIGNAL_FLAGS_NONE, on_setting_changed, &observer,
      NULL);

  Mode mode;
  bool ok = read_mode(bus, &mode, error);
  /* From here on the loop sees stop requests, or they are absorbed. */
  stop_ends_process = 0;
  if (ok) {
    observe(mode, data);
    /* Only now: the read may have just started the portal by activation. */
    PortalPresence presence = {loop, false};
    guint watch = g_bus_watch_name_on_connection(
        bus, PORTAL_NAME, G_BUS_NAME_WATCHER_FLAGS_NONE, NULL,
        on_portal_vanished, &presence, NULL);
    g_main_loop_run(loop);
    g_bus_unwatch_name(watch);
    if (presence.vanished) {
      *error = strdup("the desktop portal went away");
      ok = false;
    }
  }
  g_source_remove(stop_source);
  g_main_loop_unref(loop);
  g_dbus_connection_signal_unsubscribe(bus, subscription);
  g_object_unref(bus);
  return ok;
}
