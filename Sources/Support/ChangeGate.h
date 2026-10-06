// "Has this changed since I last wrote it?" for files that are rewritten often
// but rarely differ. A write is skipped while the content signature is the same
// and the last write is younger than `maxAge`; after that it is rewritten
// regardless, so a reader never sees a file that went stale.
//
// The signature is a 64-bit FNV-1a over the fields that matter. It replaced a
// full JSON serialisation of every row just to be compared and thrown away,
// which for 600+ Pikmin cost more than the write it was avoiding. A collision
// only delays a rewrite until `maxAge`.
#pragma once
#import <Foundation/Foundation.h>

extern const uint64_t kPKHashSeed;
uint64_t pkHash(uint64_t h, const void *bytes, size_t length);       // chain it: h = pkHash(pkHash(seed, a), b)

typedef struct { uint64_t last; BOOL have; NSTimeInterval lastWrite; } PKChangeGate;

// YES: skip the write. NO: write now (this signature is recorded as written).
BOOL pkChangeGateSkip(PKChangeGate *gate, uint64_t signature, NSTimeInterval now, NSTimeInterval maxAge);
