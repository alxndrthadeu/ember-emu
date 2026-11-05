// Process entry.
//
// Ember owns UIApplicationMain, so the app starts in its own UI (the
// library). libSDL2main is not linked: SDL's main() and app delegate
// never run. The engine starts later, when a game is picked, through
// EmberRunEngine -> mkxp_run_app.

#import <UIKit/UIKit.h>

#import "app_bridge.h"
#import "EmberEngine.h"
#import <SDL_events.h>

// UIKit needs an application delegate class. The scene delegate
// (named in Info.plist) builds the UI.
@interface EmberAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation EmberAppDelegate

// Picks the scene configuration (Info.plist) for each role: the app's
// window, or the TV's (AirPlay screen mirroring or a cable). Answering
// here, instead of leaving it to the plist alone, makes sure iOS hands
// Ember the TV instead of mirroring the iPhone.
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options {
    EmberTrail([NSString stringWithFormat:@"scene pedida: %@", session.role]);
    if ([session.role isEqualToString:UIWindowSceneSessionRoleExternalDisplayNonInteractive]) {
        return [[UISceneConfiguration alloc] initWithName:@"TV" sessionRole:session.role];
    }
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:session.role];
}

@end

static int gArgc;
static char **gArgv;

int EmberRunEngine(void) {
    return mkxp_run_app(gArgc, gArgv);
}

void EmberTrail(NSString *line) {
    // Library/Application Support/Logs/system.log: app events outside a
    // game session (TV connections), readable from the Mac.
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [support URLByAppendingPathComponent:@"Logs" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *file = [folder URLByAppendingPathComponent:@"system.log"];
    NSString *stamp = [NSDateFormatter localizedStringFromDate:NSDate.date
                                                     dateStyle:NSDateFormatterShortStyle
                                                     timeStyle:NSDateFormatterMediumStyle];
    NSData *data = [[NSString stringWithFormat:@"%@ %@\n", stamp, line] dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:file.path];
    if (!handle) {
        [data writeToURL:file atomically:YES];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

void EmberNotifyViewResized(int width, int height) {
    SDL_Event event;
    SDL_zero(event);
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_SIZE_CHANGED;
    event.window.data1 = width;
    event.window.data2 = height;
    SDL_PushEvent(&event);
}

int main(int argc, char *argv[]) {
    gArgc = argc;
    gArgv = argv;
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass(EmberAppDelegate.class));
    }
}
