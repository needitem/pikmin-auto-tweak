#import "TestKit.h"
#import "ChangeGate.h"

void test_hash(void) {
    uint64_t a = pkHash(kPKHashSeed, "abc", 3), b = pkHash(kPKHashSeed, "abc", 3), c = pkHash(kPKHashSeed, "abd", 3);
    CHECK(a == b);                                       // deterministic
    CHECK(a != c);                                       // sensitive to content
    CHECK(pkHash(pkHash(kPKHashSeed, "a", 1), "b", 1) != pkHash(pkHash(kPKHashSeed, "b", 1), "a", 1));   // and to order
    CHECK(pkHash(kPKHashSeed, "", 0) == kPKHashSeed);
}

void test_changegate(void) {
    PKChangeGate g = {0};
    CHECK(!pkChangeGateSkip(&g, 42, 0, 60));             // first time: write
    CHECK(pkChangeGateSkip(&g, 42, 10, 60));             // same content, young: skip
    CHECK(pkChangeGateSkip(&g, 42, 59.9, 60));
    CHECK(!pkChangeGateSkip(&g, 42, 60, 60));            // same content but a minute old: rewrite anyway
    CHECK(pkChangeGateSkip(&g, 42, 61, 60));             // ...and the clock restarted at that write
    CHECK(!pkChangeGateSkip(&g, 43, 62, 60));            // changed: write
    CHECK(pkChangeGateSkip(&g, 43, 63, 60));
    CHECK(!pkChangeGateSkip(&g, 42, 64, 60));            // back to the old content is still a change
}
