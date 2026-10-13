/*
 * stop.c
 *
 * The SIGINT/SIGTERM handler every backend's Watcher uses. See stop.h.
 */

#include "stop.h"

#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static StopHook stop_hook;
static volatile sig_atomic_t stop_ends_process;

static void request_stop(int signum) {
  (void)signum;
  if (stop_ends_process) {
    _exit(EXIT_SUCCESS);
  }
  int saved_errno = errno;
  if (stop_hook != NULL) {
    stop_hook();
  }
  errno = saved_errno;
}

bool catch_stop_requests(StopHook hook, char **error) {
  static bool caught;
  if (caught) {
    return true;
  }
  stop_hook = hook;
  struct sigaction action = {0};
  action.sa_handler = request_stop;
  action.sa_flags = SA_RESTART;
  sigemptyset(&action.sa_mask);
  /* If SIGTERM's install fails, undo SIGINT's: SIGTERM's never happened. */
  if (sigaction(SIGINT, &action, NULL) != 0 ||
      sigaction(SIGTERM, &action, NULL) != 0) {
    *error = strdup(strerror(errno));
    signal(SIGINT, SIG_DFL);
    return false;
  }
  caught = true;
  return true;
}

void set_stop_ends_process(bool ends) { stop_ends_process = ends; }
