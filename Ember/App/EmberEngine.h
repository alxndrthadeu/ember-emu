#ifndef EMBER_ENGINE_H
#define EMBER_ENGINE_H

// Runs the engine on the main thread until the game ends.
//
// Call it from RunLoop.main.perform, never from a main-queue block:
// it holds the main thread for the whole session, and a blocked main
// queue deadlocks the engine (see mkxp_run_app in app_bridge.h).
int EmberRunEngine(void);

// From OpenAL, linked in through the engine. The listener's gain
// scales every sound the game plays: Ember's "Som do jogo" switch.
// (Declared here so the app needs none of the engine's headers.)
void alListenerf(int param, float value);
void alGetListenerf(int param, float *value);

#ifdef __OBJC__
#import <Foundation/Foundation.h>
// Appends a line to Library/Application Support/Logs/system.log.
void EmberTrail(NSString *line);
#endif

// Tells the engine its view now has this size in points (moved to or
// from a TV): the same window event a rotation sends, through SDL's
// public SDL_PushEvent.
void EmberNotifyViewResized(int width, int height);

#endif
