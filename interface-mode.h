/*
 * interface-mode.h
 *
 * The seam between the platform-neutral command-line contract (cli.c) and
 * a platform backend that knows how to read the Interface Mode.
 */

#ifndef INTERFACE_MODE_H
#define INTERFACE_MODE_H

#include <stdbool.h>

typedef enum { MODE_LIGHT, MODE_DARK } Mode;

/*
 * Read the current Interface Mode. On failure returns false and sets *error
 * to a malloc'ed message the caller frees.
 */
bool platform_read_mode(Mode *mode, char **error);

typedef void (*ModeCallback)(Mode mode, void *data);

/*
 * Call `observe` with the current Interface Mode, then again whenever it may
 * have changed (possibly with the same mode), until SIGINT or SIGTERM: then
 * return true. From then on further SIGINT/SIGTERM are absorbed, so the
 * caller can finish and exit cleanly however many stop requests arrive. A
 * stop request before the mode is first read ends the process at once with
 * status 0, as a stopped Watcher exits. If the mode can no longer be
 * followed, return false and set *error as platform_read_mode does.
 */
bool platform_watch(ModeCallback observe, void *data, char **error);

#endif
