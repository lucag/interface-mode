/*
 * stop.h
 *
 * How a Watcher takes SIGINT and SIGTERM, shared by the platform backends
 * (docs/adr/0003): a stopped Watcher always exits 0, however and whenever it
 * is stopped.
 */

#ifndef STOP_H
#define STOP_H

#include <stdbool.h>

/* Called from the signal handler for each stop request, so it must be
 * async-signal-safe. */
typedef void (*StopHook)(void);

/*
 * Install the handler for SIGINT and SIGTERM. It stays installed for the
 * rest of the process, so a further request during shutdown (Ctrl+C reaching
 * a whole process group, then a parent asking again) is absorbed instead of
 * killing the Watcher on its way out, whichever thread it is delivered to.
 * It hands each request to `hook` (which may be NULL), unless stops end the
 * process. Only the first call installs anything; later ones return true.
 * On failure returns false and sets *error to a malloc'ed message.
 */
bool catch_stop_requests(StopHook hook, char **error);

/*
 * While set, a stop request ends the process at once with status 0. Set it
 * while the Watcher may block before its loop runs (connecting, the first
 * read): there is nothing to undo then, and every Report so far is flushed.
 */
void set_stop_ends_process(bool ends);

#endif
