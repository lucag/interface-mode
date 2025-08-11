/*
 * To compile objective-c on the command line:
 *
 * clang -framework Foundation objc-gcc.m
 *
 * You may have to link with -lobjc or other libs,
 * as required.
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <libgen.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void usage(char *progname) {
  fprintf(stdout,
          "Usage: %s [ -v | -h ]\n"
          "       -v: verbose: prints Light or Dark\n"
          "       -h: help: prints this usage\n\n"
          "The exit value is 0 for light, -1 for dark.\n",
          progname);
}

int main(int argc, char **argv) {

  NSString *defaultMode = [[NSUserDefaults standardUserDefaults]
      stringForKey:@"AppleInterfaceStyle"];

  NSString *mode = defaultMode != nil ? @"Light" : @"Dark";
  /* bool light = defaultMode != nil ? true : false; */

  NSString *appearance =
      [[[NSApplication sharedApplication] effectiveAppearance] name];

  bool light =
      /* strcasestr([appearance UTF8String], "dark") == NULL ? true : false; */
      ![appearance localizedCaseInsensitiveContainsString:@"dark"];
  /* NSLog(@"%@", mode); */
  /* NSLog(@"%@", appearance); */

  if (argc == 2) {
    if (strcmp(argv[1], "-v") == 0)
      fprintf(stdout, "%s\n", light ? "Light" : "Dark");
    else if (strcmp(argv[1], "-h") == 0)
      usage(basename(argv[0]));
  }
  exit(light ? 0 : -1);
}
