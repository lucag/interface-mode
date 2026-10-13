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

#endif
