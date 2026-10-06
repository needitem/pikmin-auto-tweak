#import "ChangeGate.h"

const uint64_t kPKHashSeed = 0xcbf29ce484222325ULL;

uint64_t pkHash(uint64_t h, const void *bytes, size_t length) {
    const unsigned char *b = (const unsigned char *)bytes;
    while (length--) { h ^= *b++; h *= 0x100000001b3ULL; }
    return h;
}

BOOL pkChangeGateSkip(PKChangeGate *g, uint64_t signature, NSTimeInterval now, NSTimeInterval maxAge) {
    if (g->have && g->last == signature && now - g->lastWrite < maxAge) return YES;
    g->last = signature; g->have = YES; g->lastWrite = now;
    return NO;
}
