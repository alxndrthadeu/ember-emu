// Process entry.
//
// Ember owns UIApplicationMain, so the app starts in its own UI (the
// library). libSDL2main is not linked: SDL's main() and app delegate
// never run. The engine starts later, when a game is picked, through
// EmberRunEngine -> mkxp_run_app.

#import <UIKit/UIKit.h>

#import "app_bridge.h"
#import "EmberEngine.h"

// UIKit needs an application delegate class. The scene delegate
// (named in Info.plist) builds the UI.
@interface EmberAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation EmberAppDelegate
@end

static int gArgc;
static char **gArgv;

int EmberRunEngine(void) {
    return mkxp_run_app(gArgc, gArgv);
}

int main(int argc, char *argv[]) {
    gArgc = argc;
    gArgv = argv;
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass(EmberAppDelegate.class));
    }
}
