#import "TestKit.h"

void test_backoff(void); void test_backoff_signature(void); void test_backoff_prune(void);
void test_troop_decor_first(void); void test_troop_seven_hearts_done(void); void test_troop_respects_movable(void);
void test_troop_colour_balance(void); void test_troop_under4_first(void); void test_troop_need_and_elite(void);
void test_troop_summary(void);

#define RUN(fn) do { int before = gFailures; fn(); printf("%s %s\n", gFailures == before ? "ok  " : "FAIL", #fn); } while (0)

int main(void) {
    @autoreleasepool {
        RUN(test_backoff); RUN(test_backoff_signature); RUN(test_backoff_prune);
        RUN(test_troop_decor_first); RUN(test_troop_seven_hearts_done); RUN(test_troop_respects_movable);
        RUN(test_troop_colour_balance); RUN(test_troop_under4_first); RUN(test_troop_need_and_elite);
        RUN(test_troop_summary);
        printf("\n%d checks, %d failed\n", gChecks, gFailures);
    }
    return gFailures ? 1 : 0;
}
