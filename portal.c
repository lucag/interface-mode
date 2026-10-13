/*
 * portal.c
 *
 * Linux backend: reads the Interface Mode from the XDG Desktop Portal
 * (org.freedesktop.appearance color-scheme). See docs/adr/0001.
 */

#include "interface-mode.h"

#include <gio/gio.h>
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

/* Strip any number of variant wrappers from a (v) reply; returns a new ref. */
static GVariant *unwrap(GVariant *reply) {
  GVariant *value = g_variant_get_child_value(reply, 0);
  while (g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
    GVariant *inner = g_variant_get_variant(value);
    g_variant_unref(value);
    value = inner;
  }
  return value;
}

bool platform_read_mode(Mode *mode, char **error) {
  GError *err = NULL;
  GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &err);
  if (bus == NULL) {
    *error = strdup(err->message);
    g_error_free(err);
    return false;
  }

  GVariant *reply = call_settings(bus, "ReadOne", &err);
  /* Portals before Settings version 2 only have the deprecated Read. */
  if (reply == NULL &&
      g_error_matches(err, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD)) {
    g_clear_error(&err);
    reply = call_settings(bus, "Read", &err);
  }
  g_object_unref(bus);
  if (reply == NULL) {
    *error = strdup(err->message);
    g_error_free(err);
    return false;
  }

  GVariant *value = unwrap(reply);
  g_variant_unref(reply);
  if (!g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) {
    *error = g_strdup_printf("unexpected color-scheme type '%s' from portal",
                             g_variant_get_type_string(value));
    g_variant_unref(value);
    return false;
  }
  *mode = g_variant_get_uint32(value) == COLOR_SCHEME_PREFER_DARK ? MODE_DARK
                                                                  : MODE_LIGHT;
  g_variant_unref(value);
  return true;
}
