/*
 * interface-mode-server.m
 *
 * A server that continuously monitors macOS interface mode changes
 * and outputs JSON messages when the state changes.
 *
 * To compile:
 * clang -framework AppKit -framework Foundation interface-mode-server.m -o
 * interface-mode-server
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Global variables for cleanup
static bool shouldExit = false;

// Signal handler for graceful shutdown
void signalHandler(int signal) {
  shouldExit = true;
  printf("\n");
  fflush(stdout);
}

@interface InterfaceModeServer : NSObject
@property(nonatomic, strong) NSAppearance *currentAppearance;
@property(nonatomic, assign) BOOL isLightMode;
@property(nonatomic, strong) NSDateFormatter *timestampFormatter;
@property(nonatomic, assign) BOOL jsonOutput;
@property(nonatomic, assign) BOOL simpleOutput;
@end

@implementation InterfaceModeServer

- (instancetype)init {
  self = [super init];
  if (self) {
    _timestampFormatter = [[NSDateFormatter alloc] init];
    _timestampFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    _timestampFormatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    _timestampFormatter.locale =
        [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];

    _jsonOutput = YES;
    _simpleOutput = NO;

    // Initialize current state
    [self updateCurrentState];
  }
  return self;
}

- (void)dealloc {
  [self cleanup];
  [super dealloc];
}

- (void)cleanup {
  [[NSApplication sharedApplication] removeObserver:self
                                         forKeyPath:@"effectiveAppearance"];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateCurrentState {
  NSAppearance *appearance =
      [[NSApplication sharedApplication] effectiveAppearance];
  self.currentAppearance = appearance;

  NSString *appearanceName = [appearance name];
  BOOL newLightMode =
      ![appearanceName localizedCaseInsensitiveContainsString:@"dark"];

  self.isLightMode = newLightMode;
}

- (void)setupNotifications {
  // Observe effectiveAppearance changes using self as observer
  [[NSApplication sharedApplication] addObserver:self
                                      forKeyPath:@"effectiveAppearance"
                                         options:NSKeyValueObservingOptionNew
                                         context:nil];

  // Set up notification for appearance changes
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleAppearanceChange:)
             name:NSApplicationDidChangeScreenParametersNotification
           object:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  if ([keyPath isEqualToString:@"effectiveAppearance"]) {
    [self checkAndReportStateChange];
  }
}

- (void)handleAppearanceChange:(NSNotification *)notification {
  [self checkAndReportStateChange];
}

- (void)checkAndReportStateChange {
  // Get new state
  NSAppearance *newAppearance =
      [[NSApplication sharedApplication] effectiveAppearance];
  NSString *appearanceName = [newAppearance name];
  BOOL newMode =
      ![appearanceName localizedCaseInsensitiveContainsString:@"dark"];

  // Check if state changed
  if (newMode != self.isLightMode) {
    BOOL oldMode = self.isLightMode;
    self.isLightMode = newMode;
    self.currentAppearance = newAppearance;

    [self outputStateChange:newMode oldMode:oldMode];
  }
}

- (void)outputStateChange:(BOOL)newLightMode oldMode:(BOOL)oldLightMode {
  NSString *newMode = newLightMode ? @"light" : @"dark";
  NSString *changeType = [NSString
      stringWithFormat:@"%@_to_%@", oldLightMode ? @"light" : @"dark", newMode];

  if (self.simpleOutput) {
    printf("%s\n", [newMode UTF8String]);
  } else if (self.jsonOutput) {
    NSString *timestamp =
        [self.timestampFormatter stringFromDate:[NSDate date]];
    NSString *jsonOutput = [NSString
        stringWithFormat:
            @"{\"timestamp\":\"%@\",\"mode\":\"%@\",\"change\":\"%@\"}\n",
            timestamp, newMode, changeType];
    printf("%s", [jsonOutput UTF8String]);
  }

  fflush(stdout);
}

- (void)run {
  // Set up signal handlers
  signal(SIGINT, signalHandler);
  signal(SIGTERM, signalHandler);

  // Initialize NSApplication
  [NSApplication sharedApplication];

  // Set up notifications
  [self setupNotifications];

  // Output initial state
  [self outputStateChange:self.isLightMode oldMode:!self.isLightMode];

  // Run the event loop
  while (!shouldExit) {
    @autoreleasepool {
      [[NSRunLoop currentRunLoop]
             runMode:NSDefaultRunLoopMode
          beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    }
  }

  // Cleanup
  [self cleanup];
}

@end

void usage(char *progname) {
  fprintf(stdout,
          "Usage: %s [OPTIONS]\n"
          "       -j, --json     Output in JSON format (default)\n"
          "       -s, --simple   Output simple text format\n"
          "       -h, --help     Show this help message\n\n"
          "The server continuously monitors macOS interface mode changes\n"
          "and outputs messages when the state changes.\n\n"
          "JSON output format:\n"
          "  "
          "{\"timestamp\":\"2024-01-15T14:30:25.123Z\",\"mode\":\"dark\","
          "\"change\":\"light_to_dark\"}\n\n"
          "Simple output format:\n"
          "  light\n"
          "  dark\n",
          progname);
}

int main(int argc, char **argv) {
  InterfaceModeServer *server = [[InterfaceModeServer alloc] init];

  // Parse command line arguments
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
      usage(argv[0]);
      return 0;
    } else if (strcmp(argv[i], "-j") == 0 || strcmp(argv[i], "--json") == 0) {
      server.jsonOutput = YES;
      server.simpleOutput = NO;
    } else if (strcmp(argv[i], "-s") == 0 || strcmp(argv[i], "--simple") == 0) {
      server.simpleOutput = YES;
      server.jsonOutput = NO;
    } else {
      fprintf(stderr, "Unknown option: %s\n", argv[i]);
      usage(argv[0]);
      return 1;
    }
  }

  // Run the server
  [server run];

  return 0;
}
