// Requests that tend to arrive in a burst (a harvest of 90 Pikmin is 18 of them
// in one tick) go through here instead of being sent on the spot. They are
// queued and released one at a time, a quarter of a second apart, and only while
// the gate says the main thread is keeping up; a request that has waited too
// long is sent anyway. The game handles each request's answer on the main
// thread, and a burst of them was what froze it.
//
// `send` runs on the main thread, later, and builds and sends the request itself
// (so it must capture ids as text, never game pointers).
#pragma once
#import <Foundation/Foundation.h>

void pkRpcDefer(void (^send)(void));
void pkRpcSetGate(BOOL (^calm)(void));          // NO = the main thread is busy, hold the queue
BOOL pkRpcPump(NSTimeInterval now);             // release at most one request; the timer calls it, tests too
NSString *pkRpcQueueStats(void);                // "예약 n · 강제 n · 대기 n (최대 n)" since the previous call
