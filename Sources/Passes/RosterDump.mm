#import "Passes.h"
#import "ChangeGate.h"
#import "Clock.h"
#import "Log.h"
#import "Roster.h"
#import "RosterReport.h"
#import "SharedFile.h"

// roster.json / roster.txt, for planning mushroom battles. Rewritten only when
// what they show changed or once a minute regardless: the first cut wrote every
// few seconds and drew an iOS diskwrites report.
static const NSTimeInterval kMinRewrite = 60.0;

void pkRosterDumpPass(void) {
    NSArray<PKPikmin *> *all = pkRoster();
    if (!all) return;
    static PKChangeGate gate;
    if (pkChangeGateSkip(&gate, pkRosterSignature(all), pkMono(), kMinRewrite)) return;

    pkWriteShared(@"roster.json", pkRosterJson(all, [NSDate date].timeIntervalSince1970));
    pkWriteShared(@"roster.txt", pkRosterSummary(all));
    PALOG(@"[로스터] %lu마리 기록", (unsigned long)all.count);
}
