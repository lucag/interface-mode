/*
 * cli.c
 *
 * The interface-mode command-line contract, shared by every platform.
 */

#include "interface-mode.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { EXIT_LIGHT = 0, EXIT_DARK = 1, EXIT_ERROR = 2 };

typedef enum { FORMAT_NONE, FORMAT_TEXT, FORMAT_JSON } Format;

static bool is_option(const char *arg, const char *shrt, const char *lng) {
  return strcmp(arg, shrt) == 0 || strcmp(arg, lng) == 0;
}

static const char *mode_name(Mode mode) {
  return mode == MODE_DARK ? "dark" : "light";
}

static void usage(FILE *out) {
  fprintf(out,
          "Usage: interface-mode [ -t | --text | -j | --json ] [ -w | --watch ]\n"
          "\n"
          "Query the desktop's Interface Mode (light or dark), or watch it.\n"
          "\n"
          "  -t, --text     print \"light\" or \"dark\" (-v, --verbose: same)\n"
          "  -j, --json     print {\"timestamp\":...,\"mode\":\"light|dark\"}\n"
          "  -w, --watch    keep running: report the mode now and on every\n"
          "                 change, one line each (JSON unless --text)\n"
          "  -h, --help     show this help\n"
          "\n"
          "Exit status: 0 light, 1 dark, 2 error (bad option, or the mode\n"
          "can't be determined). With --watch: 0 when stopped by a signal.\n");
}

/* Print one Report for `mode` in `format`, and flush it. */
static void print_report(Format format, Mode mode) {
  if (format == FORMAT_TEXT) {
    printf("%s\n", mode_name(mode));
  } else if (format == FORMAT_JSON) {
    struct timespec now;
    struct tm utc;
    char stamp[sizeof "yyyy-mm-ddThh:mm:ss"];
    clock_gettime(CLOCK_REALTIME, &now);
    gmtime_r(&now.tv_sec, &utc);
    strftime(stamp, sizeof stamp, "%Y-%m-%dT%H:%M:%S", &utc);
    printf("{\"timestamp\":\"%s.%03ldZ\",\"mode\":\"%s\"}\n", stamp,
           now.tv_nsec / 1000000, mode_name(mode));
  }
  fflush(stdout);
}

/* Report a usage error and return the exit status for it. */
static int usage_error(const char *fmt, const char *arg) {
  fprintf(stderr, "interface-mode: ");
  fprintf(stderr, fmt, arg);
  fprintf(stderr, "\n\n");
  usage(stderr);
  return EXIT_ERROR;
}

/* Turns the backend's observations into Reports: one per new mode. */
typedef struct {
  Format format;
  bool reported;
  Mode last;
} Reporter;

static void report_if_changed(Mode mode, void *data) {
  Reporter *reporter = data;
  if (reporter->reported && reporter->last == mode) {
    return;
  }
  reporter->reported = true;
  reporter->last = mode;
  print_report(reporter->format, mode);
}

static int watch(Format format) {
  Reporter reporter = {format == FORMAT_NONE ? FORMAT_JSON : format, false,
                       MODE_LIGHT};
  char *error = NULL;
  if (!platform_watch(report_if_changed, &reporter, &error)) {
    fprintf(stderr, "interface-mode: %s\n", error);
    free(error);
    return EXIT_ERROR;
  }
  return EXIT_SUCCESS;
}

int main(int argc, char **argv) {
  Format format = FORMAT_NONE;
  bool watching = false;
  for (int i = 1; i < argc; i++) {
    Format requested;
    if (is_option(argv[i], "-w", "--watch")) {
      watching = true;
      continue;
    } else if (is_option(argv[i], "-t", "--text") ||
        is_option(argv[i], "-v", "--verbose")) {
      requested = FORMAT_TEXT;
    } else if (is_option(argv[i], "-j", "--json")) {
      requested = FORMAT_JSON;
    } else if (is_option(argv[i], "-h", "--help")) {
      usage(stdout);
      return EXIT_SUCCESS;
    } else {
      return usage_error("unknown option: %s", argv[i]);
    }
    if (format != FORMAT_NONE && format != requested) {
      return usage_error("%s conflicts with an earlier format option",
                         argv[i]);
    }
    format = requested;
  }
  if (watching) {
    return watch(format);
  }

  Mode mode;
  char *error = NULL;
  if (!platform_read_mode(&mode, &error)) {
    fprintf(stderr, "interface-mode: %s\n", error);
    free(error);
    return EXIT_ERROR;
  }
  print_report(format, mode);
  return mode == MODE_DARK ? EXIT_DARK : EXIT_LIGHT;
}
