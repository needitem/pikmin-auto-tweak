#import "TestKit.h"
#import "Governor.h"

// Launch at t=0. The first 75 s belong to the game loading.
void test_governor_startup_quiet(void) {
    pkGovernorStart(0);
    CHECK(!pkGovernorAllowWork(1));
    CHECK(!pkGovernorAllowWork(74.9));
    CHECK(pkGovernorAllowWork(75));
    CHECK(pkGovernorAllowWork(80));
}

// Everything is overdue after the quiet period / a resume: the caller is told once to spread the work.
void test_governor_restagger(void) {
    pkGovernorStart(0);
    CHECK(pkGovernorTakeRestagger());              // at launch
    CHECK(!pkGovernorTakeRestagger());             // only once
    pkGovernorRequestRestagger();                  // the scheduler saw a long gap
    CHECK(pkGovernorTakeRestagger());
    CHECK(!pkGovernorTakeRestagger());
}

// A timer that fires late means the main thread is busy: hold off for 3 s.
void test_governor_stall_holds_work(void) {
    pkGovernorStart(0);
    pkGovernorNoteTimer(100);                      // first fire: nothing to compare with
    CHECK(pkGovernorCalm(100));
    pkGovernorNoteTimer(101.5);                    // 0.5 s late
    CHECK(!pkGovernorCalm(102));
    CHECK(!pkGovernorCalm(104.4));
    CHECK(pkGovernorCalm(104.5));                  // 101.5 + 3
    CHECK(!pkGovernorAllowWork(102));
    CHECK(pkGovernorAllowWork(104.5));

    pkGovernorStart(0);
    pkGovernorNoteTimer(100);
    pkGovernorNoteTimer(101.1);                    // 0.1 s late: below the threshold, not a stall
    CHECK(pkGovernorCalm(101.2));
    CHECK(pkGovernorAllowWork(101.2));
}

// A game that is busy for good must not starve the passes: after 15 s of holds, work runs anyway.
void test_governor_max_hold(void) {
    pkGovernorStart(0);
    pkGovernorNoteTimer(100);
    pkGovernorNoteTimer(102);                      // 1 s late: a stall, calm again only at 105
    CHECK(!pkGovernorAllowWork(103));              // the first held tick starts the 15 s clock
    double ranAt = 0;
    for (double t = 104; t <= 140; t += 1) {
        if ((int)t % 2 == 0) pkGovernorNoteTimer(t);   // the timer keeps firing 1 s late, so the game never calms down
        if (pkGovernorAllowWork(t)) { ranAt = t; break; }
    }
    CHECK(ranAt >= 118);                           // 103 + 15
    CHECK(ranAt <= 119);
    // once it ran, the hold clock starts over
    pkGovernorNoteTimer(ranAt + 2);
    CHECK(!pkGovernorAllowWork(ranAt + 2));
}

// Coming back from the background is not a stall.
void test_governor_inactive_resets(void) {
    pkGovernorStart(0);
    pkGovernorNoteTimer(100);
    pkGovernorNoteInactive();
    pkGovernorNoteTimer(500);                      // 400 s later: no baseline, so no lateness
    CHECK(pkGovernorCalm(500));
    PKGovernorStats s = pkGovernorTakeStats();
    CHECK_EQ(s.over100, 0);
}

// Late-timer statistics are per heartbeat and reset when read.
void test_governor_stats(void) {
    pkGovernorStart(0);
    pkGovernorNoteTimer(10);
    pkGovernorNoteTimer(11.15);                    // 0.15 s late
    pkGovernorNoteTimer(13.0);                     // 0.85 s late
    pkGovernorNoteTimer(14.0);                     // on time
    PKGovernorStats s = pkGovernorTakeStats();
    CHECK_EQ(s.over100, 2);
    CHECK_EQ(s.over500, 1);
    CHECK(s.lateMaxMs > 849 && s.lateMaxMs < 851);
    PKGovernorStats again = pkGovernorTakeStats();
    CHECK_EQ(again.over100, 0);
    CHECK(again.lateMaxMs == 0);
}

// Ticks that were held are counted for the heartbeat.
void test_governor_held_ticks_counted(void) {
    pkGovernorStart(0);
    CHECK(!pkGovernorAllowWork(10));               // startup quiet is not a "held" tick
    pkGovernorNoteTimer(100); pkGovernorNoteTimer(102);
    CHECK(!pkGovernorAllowWork(103)); CHECK(!pkGovernorAllowWork(104));
    CHECK_EQ(pkGovernorTakeStats().heldTicks, 2);
}
