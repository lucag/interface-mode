/*
 * macos.m
 *
 * macOS backend: reads the Interface Mode from AppKit's effective appearance
 * and follows its changes. See docs/adr/0002.
 */

#include "interface-mode.h"

#import <AppKit/AppKit.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Ask AppKit; any appearance whose name contains "dark" counts as Dark. */
static Mode current_mode(void) {
  @autoreleasepool {
    NSString *name = NSApplication.sharedApplication.effectiveAppearance.name;
    return [name localizedCaseInsensitiveContainsString:@"dark"] ? MODE_DARK
                                                                 : MODE_LIGHT;
  }
}

bool platform_read_mode(Mode *mode, char **error) {
  (void)error;
  *mode = current_mode();
  return true;
}

/*
 * SIGINT and SIGTERM ask the Watcher to stop (docs/adr/0003). Their handler
 * stays installed for the rest of the process, so a further request during
 * shutdown is absorbed instead of killing the Watcher on its way out. The
 * stop itself comes from dispatch sources on the main queue, which see every
 * signal whatever its handler does.
 *
 * Connecting to the window server and the first read can block, and the run
 * loop isn't running yet to serve those sources; there is nothing to undo
 * either, and every Report so far has been flushed. So while
 * stop_ends_process is set, a stop request ends the process at once, with
 * the status a stopped Watcher exits with.
 */
static volatile sig_atomic_t stop_ends_process;

static void request_stop(int signum) {
  (void)signum;
  if (stop_ends_process) {
    _exit(EXIT_SUCCESS);
  }
}

/* One per stop signal; kept for the life of the process. */
static dispatch_source_t stop_sources[2];

static bool catch_stop_requests(char **error) {
  if (stop_sources[0] != nil) {
    return true;
  }
  struct sigaction action = {0};
  action.sa_handler = request_stop;
  action.sa_flags = SA_RESTART;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGINT, &action, NULL) != 0 ||
      sigaction(SIGTERM, &action, NULL) != 0) {
    *error = strdup(strerror(errno));
    signal(SIGINT, SIG_DFL);
    return false;
  }
  int signals[] = {SIGINT, SIGTERM};
  for (size_t i = 0; i < 2; i++) {
    stop_sources[i] = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_SIGNAL, signals[i], 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(stop_sources[i], ^{
      CFRunLoopStop(CFRunLoopGetMain());
    });
    dispatch_resume(stop_sources[i]);
  }
  return true;
}

/* Calls back with the current mode whenever AppKit may have changed it. */
@interface AppearanceObserver : NSObject
@property(nonatomic) ModeCallback observe;
@property(nonatomic) void *data;
@end

@implementation AppearanceObserver

- (void)start {
  [NSApplication.sharedApplication addObserver:self
                                    forKeyPath:@"effectiveAppearance"
                                       options:0
                                       context:NULL];
  [NSNotificationCenter.defaultCenter
      addObserver:self
         selector:@selector(appearanceMayHaveChanged)
             name:NSApplicationDidChangeScreenParametersNotification
           object:nil];
}

- (void)stop {
  [NSApplication.sharedApplication removeObserver:self
                                       forKeyPath:@"effectiveAppearance"];
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  (void)keyPath, (void)object, (void)change, (void)context;
  [self appearanceMayHaveChanged];
}

- (void)appearanceMayHaveChanged {
  self.observe(current_mode(), self.data);
}

@end

bool platform_watch(ModeCallback observe, void *data, char **error) {
  if (!catch_stop_requests(error)) {
    return false;
  }
  stop_ends_process = 1;
  @autoreleasepool {
    [NSApplication sharedApplication];
    /* Observe before the first read, so no change can slip in between it
     * and the run loop. */
    AppearanceObserver *observer = [[AppearanceObserver alloc] init];
    observer.observe = observe;
    observer.data = data;
    [observer start];
    Mode mode = current_mode();
    /* From here on the run loop sees stop requests, or they are absorbed. */
    stop_ends_process = 0;
    observe(mode, data);
    CFRunLoopRun();
    [observer stop];
  }
  return true;
}
