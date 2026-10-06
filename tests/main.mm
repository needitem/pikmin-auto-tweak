#import "TestKit.h"

void test_backoff(void); void test_backoff_signature(void); void test_backoff_prune(void);
void test_troop_decor_first(void); void test_troop_seven_hearts_done(void); void test_troop_respects_movable(void);
void test_troop_colour_balance(void); void test_troop_under4_first(void); void test_troop_need_and_elite(void);
void test_troop_summary(void);
void test_governor_startup_quiet(void); void test_governor_restagger(void); void test_governor_stall_holds_work(void);
void test_governor_max_hold(void); void test_governor_inactive_resets(void); void test_governor_stats(void);
void test_governor_held_ticks_counted(void);
void test_pacer_one_at_a_time_in_order(void); void test_pacer_holds_while_busy(void);
void test_pacer_stale_request_is_forced(void); void test_pacer_stats(void);
void test_passtimings(void);

#define RUN(fn) do { int before = gFailures; fn(); printf("%s %s\n", gFailures == before ? "ok  " : "FAIL", #fn); } while (0)

int main(void) {
    @autoreleasepool {
        RUN(test_backoff); RUN(test_backoff_signature); RUN(test_backoff_prune);
        RUN(test_troop_decor_first); RUN(test_troop_seven_hearts_done); RUN(test_troop_respects_movable);
        RUN(test_troop_colour_balance); RUN(test_troop_under4_first); RUN(test_troop_need_and_elite);
        RUN(test_troop_summary);
        RUN(test_governor_startup_quiet); RUN(test_governor_restagger); RUN(test_governor_stall_holds_work);
        RUN(test_governor_max_hold); RUN(test_governor_inactive_resets); RUN(test_governor_stats);
        RUN(test_governor_held_ticks_counted);
        RUN(test_pacer_one_at_a_time_in_order); RUN(test_pacer_holds_while_busy);
        RUN(test_pacer_stale_request_is_forced); RUN(test_pacer_stats);
        RUN(test_passtimings);
        printf("\n%d checks, %d failed\n", gChecks, gFailures);
    }
    return gFailures ? 1 : 0;
}
