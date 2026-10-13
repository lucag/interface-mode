/*
 * portal.c
 *
 * Linux backend: reads the Interface Mode from the XDG Desktop Portal
 * (org.freedesktop.appearance color-scheme). See docs/adr/0001.
 */

#include "interface-mode.h"

#include <gio/gio.h>
#include <glib-unix.h>
#include <signal.h>
#include <string.h>

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

static gboolean quit_loop(gpointer loop) {
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
  GDBusConnection *bus = session_bus(error);
  if (bus == NULL) {
    return false;
  }
  /* Set everything up before the first read, so neither a change nor a stop
   * request can slip in between it and the loop. */
  GMainLoop *loop = g_main_loop_new(NULL, FALSE);
  guint on_sigint = g_unix_signal_add(SIGINT, quit_loop, loop);
  guint on_sigterm = g_unix_signal_add(SIGTERM, quit_loop, loop);
  Observer observer = {observe, data};
  guint subscription = g_dbus_connection_signal_subscribe(
      bus, PORTAL_NAME, SETTINGS_IFACE, "SettingChanged", PORTAL_PATH,
      APPEARANCE_NS, G_DBUS_SIGNAL_FLAGS_NONE, on_setting_changed, &observer,
      NULL);

  Mode mode;
  bool ok = read_mode(bus, &mode, error);
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
  g_source_remove(on_sigint);
  g_source_remove(on_sigterm);
  g_main_loop_unref(loop);
  g_dbus_connection_signal_unsubscribe(bus, subscription);
  g_object_unref(bus);
  return ok;
}
