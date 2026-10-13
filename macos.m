/*
 * macos.m
 *
 * macOS backend: reads the Interface Mode from AppKit's effective appearance
 * and follows its changes. See docs/adr/0002.
 */

#include "interface-mode.h"
#include "stop.h"

#import <AppKit/AppKit.h>
#include <signal.h>

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
 * Stop requests reach the run loop through dispatch sources on the main
 * queue, which see every signal whatever its handler does; the shared
 * handler (stop.h) only has to keep SIGINT and SIGTERM from killing the
 * Watcher. The sources live for one Watcher: cancelling them at the end also
 * drops a request that arrived during its shutdown, which was its.
 */
static NSArray<dispatch_source_t> *watch_stop_requests(void) {
  NSMutableArray<dispatch_source_t> *sources = [NSMutableArray array];
  for (NSNumber *signum in @[ @(SIGINT), @(SIGTERM) ]) {
    dispatch_source_t source =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, signum.intValue,
                               0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
      CFRunLoopStop(CFRunLoopGetMain());
    });
    dispatch_resume(source);
    [sources addObject:source];
  }
  return sources;
}

static void unwatch_stop_requests(NSArray<dispatch_source_t> *sources) {
  for (dispatch_source_t source in sources) {
    dispatch_source_cancel(source);
  }
}

/* Calls back with the current mode whenever AppKit may have changed it. */
@interface AppearanceObserver : NSObject
@property(nonatomic) ModeCallback callback;
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
  self.callback(current_mode(), self.data);
}

@end

bool platform_watch(ModeCallback observe, void *data, char **error) {
  if (!catch_stop_requests(NULL, error)) {
    return false;
  }
  /* Connecting to the window server and the first read can block before
   * the run loop runs. */
  set_stop_ends_process(true);
  @autoreleasepool {
    NSArray<dispatch_source_t> *stop_sources = watch_stop_requests();
    [NSApplication sharedApplication];
    /* Observe before the first read, so no change can slip in between it
     * and the run loop. */
    AppearanceObserver *observer = [[AppearanceObserver alloc] init];
    observer.callback = observe;
    observer.data = data;
    [observer start];
    Mode mode = current_mode();
    /* From here on the run loop sees stop requests, or they are absorbed. */
    set_stop_ends_process(false);
    observe(mode, data);
    CFRunLoopRun();
    [observer stop];
    unwatch_stop_requests(stop_sources);
  }
  return true;
}
