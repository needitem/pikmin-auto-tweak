// Append-only diagnostic log (Documents/pa.log). Thread-safe: hooks may log
// from any game thread.
#pragma once
#import <Foundation/Foundation.h>

void PALOG(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);

// Same, but only when the text under `key` changed or three minutes passed.
// Passes print a status line every few seconds; repeating an unchanged one is
// what once grew the log to three quarters of a megabyte in a single session.
//
// The message expression is evaluated LAZILY: a key already evaluated in the
// last two seconds skips the (often long) string formatting entirely.
BOOL pkLogAllow(NSString *key);
void pkLogEmitC(NSString *key, NSString *msg);
#define PKLOGC(key, ...) do { NSString *_pk_key = (key); if (pkLogAllow(_pk_key)) pkLogEmitC(_pk_key, __VA_ARGS__); } while (0)
