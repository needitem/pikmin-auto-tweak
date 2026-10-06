#import "TestKit.h"
#import "NectarKind.h"

// Nectar is "special" when it names a flower, or carries a kind other than plain.
void test_nectar_kind(void) {
    CHECK(!pkNectarIsSpecial(nil, 0));
    CHECK(!pkNectarIsSpecial(@"", 0));
    CHECK(!pkNectarIsSpecial(@"", 5));            // the game's COMMON kind is ordinary nectar
    CHECK(pkNectarIsSpecial(@"canna", 0));        // a named flower always is
    CHECK(pkNectarIsSpecial(@"canna", 5));
    CHECK(pkNectarIsSpecial(nil, 55));            // a kind other than 0 / 5, even without a name
    CHECK(pkNectarIsSpecial(@"", 1));
}
