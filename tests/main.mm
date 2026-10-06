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
void test_seed_tier(void); void test_seed_compare(void); void test_seed_compare_unknown_colour(void); void test_seed_sort(void);
void test_nectar_kind(void);
void test_pool_order_and_exclusions(void); void test_pool_excludes_troop_plan(void); void test_pool_falls_back_to_troop(void);
void test_pool_troop_reservation(void); void test_troop_wanted_busy_takes_a_place(void);
void test_hash(void); void test_changegate(void);
void test_roster_json_is_valid_and_complete(void); void test_roster_json_escapes_names(void);
void test_roster_json_handles_bad_numbers_and_empty(void); void test_roster_summary(void); void test_roster_signature(void);

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
        RUN(test_seed_tier); RUN(test_seed_compare); RUN(test_seed_compare_unknown_colour); RUN(test_seed_sort);
        RUN(test_nectar_kind);
        RUN(test_pool_order_and_exclusions); RUN(test_pool_excludes_troop_plan); RUN(test_pool_falls_back_to_troop);
        RUN(test_pool_troop_reservation); RUN(test_troop_wanted_busy_takes_a_place);
        RUN(test_hash); RUN(test_changegate);
        RUN(test_roster_json_is_valid_and_complete); RUN(test_roster_json_escapes_names);
        RUN(test_roster_json_handles_bad_numbers_and_empty); RUN(test_roster_summary); RUN(test_roster_signature);
        printf("\n%d checks, %d failed\n", gChecks, gFailures);
    }
    return gFailures ? 1 : 0;
}
