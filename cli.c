/*
 * cli.c
 *
 * The interface-mode command-line contract, shared by every platform.
 */

#include "interface-mode.h"

#include <stdio.h>
#include <stdlib.h>

enum { EXIT_LIGHT = 0, EXIT_DARK = 1, EXIT_ERROR = 2 };

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;

  Mode mode;
  char *error = NULL;
  if (!platform_read_mode(&mode, &error)) {
    fprintf(stderr, "interface-mode: %s\n", error);
    free(error);
    return EXIT_ERROR;
  }
  return mode == MODE_DARK ? EXIT_DARK : EXIT_LIGHT;
}
