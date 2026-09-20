#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <lua.h>
#include <stdlib.h>
#include <string.h>

#ifdef MACOS_USE_BUNDLE
void set_macos_bundle_resources(lua_State *L)
{ @autoreleasepool
{
    NSString* resource_path = [[NSBundle mainBundle] resourcePath];
    lua_pushstring(L, [resource_path UTF8String]);
    lua_setglobal(L, "MACOS_RESOURCES");
}}
#endif

/* Thanks to mathewmariani, taken from his lite-macos github repository. */
void enable_momentum_scroll() {
  [[NSUserDefaults standardUserDefaults]
    setBool: YES
    forKey: @"AppleMomentumScrollSupported"];
}

/*
 * EasyAI: open a single native picker that can select BOTH files and folders.
 * Returns a NULL-terminated array of malloc'd path strings, or NULL if cancelled.
 * Caller must free each string and the array.
 */
char **easyai_open_paths_sync(void *ns_window, const char *title, const char *location, int allow_many, int *out_count)
{
  @autoreleasepool {
    if (out_count) *out_count = 0;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = allow_many ? YES : NO;
    panel.title = (title && title[0]) ? [NSString stringWithUTF8String:title] : @"打开";
    panel.prompt = @"打开";
    if (location && location[0]) {
      panel.directoryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:location]];
    }

    NSWindow *parent = (__bridge NSWindow *)ns_window;
    NSModalResponse resp;
    if (parent) {
      [panel beginSheetModalForWindow:parent completionHandler:nil];
      // Fallback to modal run (sheet needs async bridge with SDL event loop)
      resp = [panel runModal];
    } else {
      resp = [panel runModal];
    }

    if (resp != NSModalResponseOK) {
      return NULL;
    }

    NSArray<NSURL *> *urls = [panel URLs];
    NSUInteger n = urls.count;
    if (n == 0) return NULL;
    if (out_count) *out_count = (int)n;
    char **list = calloc(n + 1, sizeof(char *));
    if (!list) return NULL;
    for (NSUInteger i = 0; i < n; i++) {
      const char *fs = urls[i].fileSystemRepresentation;
      list[i] = fs ? strdup(fs) : NULL;
    }
    return list;
  }
}

